import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/delivery_status.dart';
import '../models/rider_availability.dart';
import 'pending_registration_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  static const _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lzoxjmevvjycclfwjtks.supabase.co',
  );
  static const _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_mQt-t-8nWjJ7Bya_EVdkaA_QhZr80qu',
  );
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const riderTable = String.fromEnvironment(
    'SUPABASE_RIDER_TABLE',
    defaultValue: 'rider',
  );
  static const _riderAssetsBucket = 'rider-assets';
  static const _lastAuthEmailKey = 'last_auth_email';

  SupabaseClient get _client => Supabase.instance.client;
  String get _supabaseKey => _supabasePublishableKey.isNotEmpty
      ? _supabasePublishableKey
      : _supabaseAnonKey;

  User? get currentUser => _client.auth.currentUser;

  bool get isAuthenticated => currentUser != null;

  Future<User?> currentUserOrRestored() async {
    final user = currentUser ?? _client.auth.currentSession?.user;
    if (user != null) return user;

    try {
      final authState = await _client.auth.onAuthStateChange.first.timeout(
        const Duration(seconds: 2),
      );
      return authState.session?.user ?? currentUser;
    } catch (_) {
      return currentUser;
    }
  }

  Future<void> initialize() async {
    if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
      throw Exception(
        'Missing Supabase config. Start Flutter with '
        '--dart-define=SUPABASE_URL=... '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
      );
    }

    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await _cacheAuthEmail(email);
    return response;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    await _cacheAuthEmail(email);
    return response;
  }

  Future<void> signOut() => _client.auth.signOut();

  /// True when the project requires email confirmation and the account created
  /// by [signUp] is not usable for password sign-in yet.
  bool signUpNeedsEmailConfirmation(AuthResponse response) =>
      response.session == null && response.user?.emailConfirmedAt == null;

  Future<void> resendConfirmationEmail(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  /// Whether a rider row already exists for [email]. Used to tell a wrong
  /// password apart from an account that was registered but never confirmed.
  Future<bool> riderExistsForEmail(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    try {
      final profile = await _selectRiderByCandidates([
        MapEntry('email', trimmed),
      ]);
      return profile != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteCurrentUser() async {
    // Supabase user deletion requires a service-role key and should be done by
    // an Edge Function/admin backend. The client signs out to avoid a bad state.
    await signOut();
  }

  // Storage
  Future<String> uploadNicImage(Uint8List fileBytes, String fileName) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Sign in before uploading NIC images.');

    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = 'NIC_images/$userId/$safeFileName';

    await _client.storage
        .from(_riderAssetsBucket)
        .uploadBinary(
          path,
          fileBytes,
          fileOptions: FileOptions(
            contentType: _contentTypeForFile(safeFileName),
            upsert: true,
          ),
        )
        .timeout(const Duration(seconds: 30));

    return _client.storage.from(_riderAssetsBucket).getPublicUrl(path);
  }

  Future<String> uploadRiderProfilePhoto({
    required String riderId,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'rider_profiles/$riderId/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    await _client.storage
        .from(_riderAssetsBucket)
        .uploadBinary(
          path,
          fileBytes,
          fileOptions: FileOptions(
            contentType: _contentTypeForFile(safeFileName),
            upsert: true,
          ),
        );

    return _client.storage.from(_riderAssetsBucket).getPublicUrl(path);
  }

  // User Profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final email = currentUser?.email ?? await _cachedAuthEmail();
    final cachedProfile = await _cachedUserProfile(userId);
    final remoteProfile = await _selectRiderByCandidates(
      _riderLookupCandidates(userId, email: email),
    );
    if (remoteProfile != null) {
      await _cacheUserProfile(userId, remoteProfile);
      return remoteProfile;
    }

    return cachedProfile;
  }

  Future<Map<String, dynamic>?> getCurrentRiderProfile() async {
    final user = await currentUserOrRestored();
    final email = user?.email ?? await _cachedAuthEmail();
    final cacheId = user?.id ?? email;
    if (cacheId == null || cacheId.trim().isEmpty) return null;

    final remoteProfile = await _selectRiderByCandidates(
      _riderLookupCandidates(cacheId, email: email),
    );
    if (remoteProfile != null) {
      await _cacheUserProfile(cacheId, remoteProfile);
      if (user != null && cacheId != user.id) {
        await _cacheUserProfile(user.id, remoteProfile);
      }
      return remoteProfile;
    }

    return _cachedUserProfile(cacheId);
  }

  Future<void> completeRiderRegistration(PendingRegistrationData data) async {
    final existingProfile = await getUserProfile(data.userId);
    if (existingProfile != null) return;
    await updateRiderProfile(
      riderId: data.userId,
      data: _riderPayloadForSchema({
        'user_id': data.userId,
        'email': data.email,
        'Name': data.fullName,
        'Phone_Number': data.phoneNumber,
        'Branch': data.branch,
        'NIC': data.nicNumber,
        'Address': data.homeAddress,
        'Emergency_Contact': data.emergencyContact,
        'Vehicle_Type': data.vehicleType,
        'Vehicle_Number': data.vehicleNumber,
        'Driver_Licence_No': data.drivingLicense,
      }),
    );
  }

  Future<Map<String, dynamic>> createUserProfile({
    required String userId,
    required String fullName,
    required String email,
    String? phoneNumber,
    String? branch,
    String? nicNumber,
    String? homeAddress,
    String? emergencyContact,
    String? vehicleType,
    String? vehicleNumber,
    String? drivingLicense,
    String? nicFrontImageUrl,
    String? nicBackImageUrl,
  }) async {
    final profile = _riderPayloadForSchema({
      'id': userId,
      'user_id': userId,
      'firebase_uid': userId,
      'full_name': fullName,
      'Name': fullName,
      'email': email,
      'Email': email,
      'phone_number': phoneNumber,
      'Phone_Number': phoneNumber,
      'branch': branch,
      'Branch': branch,
      'nic_number': nicNumber,
      'NIC': nicNumber,
      'home_address': homeAddress,
      'Address': homeAddress,
      'emergency_contact': emergencyContact,
      'Emergency_Contact': emergencyContact,
      'vehicle_type': vehicleType,
      'Vehicle_Type': vehicleType,
      'vehicle_number': vehicleNumber,
      'Vehicle_No': vehicleNumber,
      'driving_license': drivingLicense,
      'Driver_Licence_No': drivingLicense,
      'nic_front_image': nicFrontImageUrl,
      'NIC_Front_Image': nicFrontImageUrl,
      'nic_back_image': nicBackImageUrl,
      'NIC_Back_Image': nicBackImageUrl,
    });

    await _updateRiderByCandidates(
      _riderLookupCandidates(userId, email: email),
      profile,
    );
    await _cacheUserProfile(userId, profile);
    return profile;
  }

  Future<void> saveRider(Map<String, dynamic> riderData) async {
    final userId =
        (riderData['id'] as String?) ??
        (riderData['user_id'] as String?) ??
        (riderData['firebase_uid'] as String?) ??
        currentUser?.id;
    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Cannot save rider without a Supabase auth user id.');
    }

    final profile = _riderPayloadForSchema({
      ...riderData,
      'user_id': userId,
      'email':
          (riderData['email'] as String?) ??
          (riderData['Email'] as String?) ??
          currentUser?.email,
    });

    await _updateRiderByCandidates(
      _riderLookupCandidates(
        userId,
        email:
            (riderData['email'] as String?) ??
            (riderData['Email'] as String?) ??
            currentUser?.email,
      ),
      profile,
    );
    await _cacheUserProfile(userId, profile);
  }

  Future<Map<String, dynamic>?> getRiderByUid(String uid) =>
      getUserProfile(uid);

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    final profile = _legacyRiderPayloadForTable({
      ...updates,
      'email':
          (updates['email'] as String?) ??
          (updates['original_email'] as String?) ??
          currentUser?.email,
    });
    final updateCandidates = _mergeRiderLookupCandidates(
      [
        _candidateFromValue('user_id', updates['original_user_id']),
        ..._riderLookupCandidates(
          userId,
          email:
              (updates['original_email'] as String?) ??
              (updates['email'] as String?) ??
              currentUser?.email,
        ),
        _candidateFromValue('NIC', updates['original_NIC']),
      ].whereType<MapEntry<String, String>>().toList(),
    );

    final updatedProfile = await _updateExistingRiderByCandidates(
      updateCandidates,
      profile,
    );
    final savedProfile =
        updatedProfile ?? await _updateBestExistingRiderProfile(profile);
    if (savedProfile == null) {
      throw Exception(
        'No matching rider row was found in Supabase. Run the rider user_id SQL setup or check the rider table.',
      );
    }
    await _cacheUserProfile(userId, savedProfile);
  }

  Future<void> updateRiderProfile({
    required String riderId,
    required Map<String, dynamic> data,
  }) async {
    final email = currentUser?.email;
    await updateUserProfile(riderId, {
      ...data,
      'user_id': riderId,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    });
  }

  /// Writes the rider's own work state to `rider.availability`.
  ///
  /// Kept separate from [updateRiderProfile] so it touches only the two
  /// availability columns; the profile payload mappers rewrite the whole
  /// identity block, which is not wanted for a one-tap status change.
  /// Column on the rider table holding the rider's own work state.
  static const availabilityColumn = 'availability_status';

  /// Optional companion column. Dropped from the write if the table does not
  /// have it, so availability still saves without it.
  static const _availabilityTimestampColumn = 'availability_updated_at';

  /// Where availability is read from, most specific first. The extra names are
  /// spellings the table has carried at different points.
  static const _availabilityReadColumns = [
    availabilityColumn,
    'availability',
    'Availability_Status',
    'Availability',
    'rider_status',
  ];

  Future<Map<String, dynamic>> updateRiderAvailability({
    required String riderId,
    required RiderAvailability availability,
  }) async {
    final candidates = _riderLookupCandidates(
      riderId,
      email: currentUser?.email ?? await _cachedAuthEmail(),
    );

    for (final candidate in candidates) {
      var payload = <String, dynamic>{
        availabilityColumn: availability.key,
        _availabilityTimestampColumn: DateTime.now().toUtc().toIso8601String(),
      };

      while (true) {
        try {
          final rows = await _client
              .from(riderTable)
              .update(payload)
              .eq(candidate.key, candidate.value)
              .select();

          final profile = _bestRiderProfile(rows);
          if (profile != null) {
            await _cacheUserProfile(riderId, profile);
            return profile;
          }
          // No row matched this lookup column; try the next candidate.
          break;
        } catch (error) {
          final missingColumn = _missingColumnFrom(error);

          if (missingColumn == availabilityColumn) {
            throw Exception(
              'The rider table has no "$availabilityColumn" column. '
              'Run docs/rider-availability.sql in the Supabase SQL editor.',
            );
          }

          if (missingColumn != null) {
            // Only the optional timestamp is left to drop; retry without it.
            final reduced = _withoutMissingColumn(payload, error);
            if (reduced != null && reduced.isNotEmpty) {
              payload = reduced;
              continue;
            }
          }

          if (_isMissingFilterColumn(error, candidate.key)) break;
          rethrow;
        }
      }
    }

    throw Exception(
      'No matching rider row was found in Supabase, so availability was not saved.',
    );
  }

  /// Availability currently stored for [profile], defaulting to offline.
  RiderAvailability availabilityFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return RiderAvailability.offline;
    for (final key in _availabilityReadColumns) {
      if (profile.containsKey(key) && profile[key] != null) {
        return RiderAvailability.fromKey(profile[key]);
      }
    }
    return RiderAvailability.offline;
  }

  // Realtime
  //
  // Assignment happens in the admin tool, so the rider's list has to react to
  // writes it did not make. Any change on trip/delivery re-runs the normal
  // authorized fetch rather than trusting the broadcast payload, which keeps
  // the trip -> delivery join in one place.

  /// Watches for delivery and trip changes. [onChange] can fire in bursts, so
  /// callers should debounce. Returns a function that cancels the subscription.
  Future<void> Function() subscribeToDeliveryChanges(void Function() onChange) {
    final channel = _client.channel(
      'rider-deliveries-${DateTime.now().millisecondsSinceEpoch}',
    );

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: deliveryTable,
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tripTable,
          callback: (_) => onChange(),
        )
        .subscribe();

    return () => _client.removeChannel(channel);
  }

  /// Watches this rider's inbox so the unread badge moves without a refresh.
  Future<void> Function() subscribeToNotifications(
    String riderId,
    void Function() onChange,
  ) {
    final channel = _client.channel(
      'rider-notifications-${DateTime.now().millisecondsSinceEpoch}',
    );

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: notificationTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rider_id',
            value: riderId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();

    return () => _client.removeChannel(channel);
  }

  // Push notifications
  //
  // The Edge Function resolves trip.rider_nic -> rider -> device_tokens, so a
  // token row carries both the auth id and the NIC.
  static const deviceTokenTable = 'device_tokens';
  static const notificationTable = 'notifications';

  /// Registers this phone for pushes. Safe to call on every launch: the row is
  /// keyed on the token, so a reinstall or token rotation replaces it.
  Future<void> saveDeviceToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;

    final user = await currentUserOrRestored();
    final riderId = user?.id;
    if (riderId == null) return;

    try {
      await _client.from(deviceTokenTable).upsert({
        'rider_id': riderId,
        'rider_nic': await _currentRiderNic(),
        'token': trimmed,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (error) {
      if (_isMissingTable(error, deviceTokenTable)) return;
      rethrow;
    }
  }

  /// Called on sign-out so the phone stops receiving the previous rider's work.
  Future<void> removeDeviceToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;

    try {
      await _client.from(deviceTokenTable).delete().eq('token', trimmed);
    } catch (error) {
      if (_isMissingTable(error, deviceTokenTable)) return;
      rethrow;
    }
  }

  Future<List<AppNotification>> getNotifications({int limit = 50}) async {
    final user = await currentUserOrRestored();
    final riderId = user?.id;
    if (riderId == null) return [];

    try {
      final List<dynamic> rows = await _client
          .from(notificationTable)
          .select()
          .eq('rider_id', riderId)
          .order('created_at', ascending: false)
          .limit(limit);

      return [
        for (final row in rows)
          if (row is Map)
            AppNotification.fromRow(Map<String, dynamic>.from(row)),
      ];
    } catch (error) {
      if (_isMissingTable(error, notificationTable)) return [];
      rethrow;
    }
  }

  Future<int> unreadNotificationCount() async {
    final user = await currentUserOrRestored();
    final riderId = user?.id;
    if (riderId == null) return 0;

    try {
      final rows = await _client
          .from(notificationTable)
          .select('id')
          .eq('rider_id', riderId)
          .isFilter('read_at', null);
      return rows.length;
    } catch (error) {
      if (_isMissingTable(error, notificationTable)) return 0;
      rethrow;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client
          .from(notificationTable)
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId)
          .isFilter('read_at', null);
    } catch (error) {
      if (_isMissingTable(error, notificationTable)) return;
      rethrow;
    }
  }

  Future<void> markAllNotificationsRead() async {
    final user = await currentUserOrRestored();
    final riderId = user?.id;
    if (riderId == null) return;

    try {
      await _client
          .from(notificationTable)
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('rider_id', riderId)
          .isFilter('read_at', null);
    } catch (error) {
      if (_isMissingTable(error, notificationTable)) return;
      rethrow;
    }
  }

  // Deliveries
  //
  // Assignment chain: rider."NIC" -> trip.rider_nic, then trip.trip_id ->
  // delivery.trip_id. Rows come back normalized onto the canonical keys the
  // screens read (id / status / pickup_address / delivery_address) with the
  // raw columns left in place alongside them.
  static const deliveryTable = 'delivery';
  static const tripTable = 'trip';

  Future<String?> _currentRiderNic() async {
    final user = await currentUserOrRestored();
    final uid = user?.id;
    if (uid == null || uid.trim().isEmpty) return null;

    final profile = await getUserProfile(uid);
    if (profile == null) return null;
    return _rowText(profile, const ['NIC', 'nic', 'nic_number']);
  }

  Future<List<Map<String, dynamic>>> getAssignedTrips() async {
    final nic = await _currentRiderNic();
    if (nic == null) return [];

    try {
      final List<dynamic> response = await _client
          .from(tripTable)
          .select()
          .eq('rider_nic', nic);
      return [
        for (final row in response)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    } catch (error) {
      if (_isMissingTable(error, tripTable)) return [];
      rethrow;
    }
  }

  /// Every delivery assigned to the signed-in rider through one of their trips.
  Future<List<Map<String, dynamic>>> getAssignedDeliveries({
    String? status,
  }) async {
    final trips = await getAssignedTrips();
    if (trips.isEmpty) return [];

    final tripsById = <String, Map<String, dynamic>>{};
    final tripIds = <dynamic>[];
    for (final trip in trips) {
      final id = trip['trip_id'];
      if (id == null) continue;
      tripsById[id.toString()] = trip;
      tripIds.add(id);
    }
    if (tripIds.isEmpty) return [];

    final List<dynamic> response;
    try {
      var query = _client
          .from(deliveryTable)
          .select()
          .inFilter('trip_id', tripIds);
      if (status != null) query = query.eq('delivery_status', status);
      response = await query;
    } catch (error) {
      if (_isMissingTable(error, deliveryTable)) return [];
      rethrow;
    }

    final deliveries = <Map<String, dynamic>>[];
    for (final row in response) {
      if (row is! Map) continue;
      final delivery = _normalizeDelivery(Map<String, dynamic>.from(row));
      final trip = tripsById[delivery['trip_id']?.toString()];
      if (trip != null) delivery['trip'] = trip;
      deliveries.add(delivery);
    }

    deliveries.sort(_compareDeliveriesNewestFirst);
    return deliveries;
  }

  /// Deliveries for the signed-in rider. Assignment only ever arrives through a
  /// trip, so this is the trip-joined lookup.
  Future<List<Map<String, dynamic>>> getDeliveries({String? status}) {
    return getAssignedDeliveries(status: status);
  }

  /// Maps `delivery` columns onto the keys the screens read.
  Map<String, dynamic> _normalizeDelivery(Map<String, dynamic> row) {
    final delivery = Map<String, dynamic>.from(row);

    final id = _rowText(row, const ['del_id', 'id']);
    if (id != null) {
      delivery['id'] = id;
      delivery.putIfAbsent('tracking_code', () => id);
      delivery.putIfAbsent('parcel_id', () => id);
    }

    delivery['status'] =
        _rowText(row, const ['delivery_status', 'status']) ?? 'pending';

    final pickup = _rowText(row, const [
      'pick_location',
      'pickup_address',
      'pickLocation',
    ]);
    if (pickup != null) delivery['pickup_address'] = pickup;

    final dropoff = _rowText(row, const [
      'drop_location',
      'delivery_address',
      'dropLocation',
    ]);
    if (dropoff != null) delivery['delivery_address'] = dropoff;

    return delivery;
  }

  String? _rowText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  Future<Map<String, dynamic>> createDelivery({
    required String pickupAddress,
    required String deliveryAddress,
    required double distance,
    required double price,
    String? packageDescription,
    String? recipientName,
    String? recipientPhone,
    double? pickupLatitude,
    double? pickupLongitude,
    double? deliveryLatitude,
    double? deliveryLongitude,
  }) async {
    // A delivery reaches the rider through a trip, so a new one is attached to
    // the rider's most recent trip.
    final trips = await getAssignedTrips();
    if (trips.isEmpty) {
      throw Exception(
        'No trip is assigned to you yet, so a delivery cannot be created.',
      );
    }
    trips.sort((a, b) {
      final aId = int.tryParse('${a['trip_id']}') ?? 0;
      final bId = int.tryParse('${b['trip_id']}') ?? 0;
      return bId.compareTo(aId);
    });

    final delivery = <String, dynamic>{
      'trip_id': trips.first['trip_id'],
      'pick_location': pickupAddress,
      'drop_location': deliveryAddress,
      'delivery_status': 'pending',
    };

    final dynamic inserted;
    try {
      inserted = await _client
          .from(deliveryTable)
          .insert(delivery)
          .select()
          .single();
    } catch (error) {
      if (_isMissingTable(error, deliveryTable)) {
        throw Exception(
          'Delivery setup is incomplete. Create the delivery table in Supabase first.',
        );
      }
      rethrow;
    }

    return _normalizeDelivery(Map<String, dynamic>.from(inserted));
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    try {
      await _client
          .from(deliveryTable)
          .update({'delivery_status': status})
          .eq('del_id', deliveryId);
    } catch (error) {
      if (_isMissingTable(error, deliveryTable)) return;
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getDeliveryById(String deliveryId) async {
    final dynamic response;
    try {
      response = await _client
          .from(deliveryTable)
          .select()
          .eq('del_id', deliveryId)
          .maybeSingle();
    } catch (error) {
      if (_isMissingTable(error, deliveryTable)) return null;
      rethrow;
    }

    if (response == null) return null;
    return _normalizeDelivery(Map<String, dynamic>.from(response));
  }

  Future<void> updateRiderLiveLocation({
    required String riderId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
  }) async {
    final now = DateTime.now().toIso8601String();
    final location = <String, dynamic>{
      'rider_id': riderId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'is_online': true,
      'updated_at': now,
    };

    await _client.from('rider_locations').upsert({
      'id': riderId,
      ...location,
    }, onConflict: 'id');

    await _updateRiderByCandidates(
      _riderLookupCandidates(riderId, email: currentUser?.email),
      {
        'firebase_uid': riderId,
        'live_location': location,
        'is_tracking': true,
        'last_location_at': now,
      },
      insertIfMissing: false,
    );

    await _updateLiveDeliveryLocations(riderId, location, now);
  }

  Future<void> markRiderLocationOffline(String riderId) async {
    final now = DateTime.now().toIso8601String();
    final offlineData = {
      'rider_id': riderId,
      'is_online': false,
      'stopped_at': now,
      'updated_at': now,
    };

    await _client.from('rider_locations').upsert({
      'id': riderId,
      ...offlineData,
    }, onConflict: 'id');

    await _updateRiderByCandidates(
      _riderLookupCandidates(riderId, email: currentUser?.email),
      {'firebase_uid': riderId, 'is_tracking': false, 'last_location_at': now},
      insertIfMissing: false,
    );

    await _updateLiveDeliveryLocations(riderId, {'is_online': false}, now);
  }

  // Statistics
  /// Delivery counters for [userId].
  ///
  /// Buckets come from [DeliveryStats] so these match the dashboard exactly.
  /// The old version matched `status == 'pending'` literally, which counted
  /// nothing once the backend started handing out 'assigned' and 'accepted'.
  Future<DeliveryStats> getRiderStats(String userId) async {
    return DeliveryStats.fromDeliveries(await getAssignedDeliveries());
  }

  Future<void> _updateLiveDeliveryLocations(
    String riderId,
    Map<String, dynamic> location,
    String updatedAt,
  ) async {
    // The delivery table carries no live-location columns, so the rider's
    // position is mirrored onto the rider row and rider_locations only.
  }

  Map<String, dynamic>? _withoutMissingColumn(
    Map<String, dynamic> payload,
    Object error,
  ) {
    final missingColumn = _missingColumnFrom(error);
    if (missingColumn == null || !payload.containsKey(missingColumn)) {
      return null;
    }

    return Map<String, dynamic>.from(payload)..remove(missingColumn);
  }

  Map<String, dynamic> _riderPayloadForSchema(Map<String, dynamic> data) {
    final payload = <String, dynamic>{};

    Object? firstValue(List<String> sourceKeys) {
      for (final key in sourceKeys) {
        if (!data.containsKey(key)) continue;
        final value = data[key];
        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        return value is String ? value.trim() : value;
      }
      return null;
    }

    void setAll(List<String> columns, List<String> sourceKeys) {
      final value = firstValue(sourceKeys);
      if (value == null) return;
      for (final column in columns) {
        payload[column] = value;
      }
    }

    setAll(
      ['id', 'user_id', 'firebase_uid'],
      ['id', 'user_id', 'firebase_uid'],
    );
    setAll(['email', 'Email'], ['email', 'Email']);
    setAll(['nic_number', 'NIC'], ['nic_number', 'NIC']);
    setAll(['full_name', 'Name'], ['full_name', 'Name']);
    setAll(['phone_number', 'Phone_Number'], ['phone_number', 'Phone_Number']);
    setAll(['branch', 'Branch'], ['branch', 'Branch']);
    setAll(['home_address', 'Address'], ['home_address', 'Address']);
    setAll(
      ['emergency_contact', 'Emergency_Contact'],
      ['emergency_contact', 'Emergency_Contact'],
    );
    setAll(['vehicle_type', 'Vehicle_Type'], ['vehicle_type', 'Vehicle_Type']);
    setAll(
      ['vehicle_number', 'Vehicle_No', 'Vehicle_Number'],
      ['vehicle_number', 'Vehicle_No', 'Vehicle_Number'],
    );
    setAll(
      ['driving_license', 'Driver_Licence_No'],
      ['driving_license', 'Driver_Licence_No'],
    );
    setAll(
      ['profile_photo_url', 'Profile_Photo_Url'],
      ['profile_photo_url', 'Profile_Photo_Url'],
    );
    setAll(['profile_completed_at'], ['profile_completed_at']);
    setAll(['updated_at'], ['updated_at']);

    return payload;
  }

  Map<String, dynamic> _legacyRiderPayloadForTable(Map<String, dynamic> data) {
    final payload = <String, dynamic>{};

    void setFirst(String column, List<String> sourceKeys) {
      for (final key in sourceKeys) {
        if (!data.containsKey(key)) continue;
        final value = data[key];
        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        payload[column] = value is String ? value.trim() : value;
        return;
      }
    }

    setFirst('NIC', ['NIC', 'nic_number']);
    setFirst('user_id', ['user_id', 'id', 'firebase_uid']);
    setFirst('Name', ['Name', 'full_name']);
    setFirst('Phone_Number', ['Phone_Number', 'phone_number']);
    setFirst('Branch', ['Branch', 'branch']);
    setFirst('email', ['email', 'Email']);
    setFirst('Address', ['Address', 'home_address']);
    setFirst('Emergency_Contact', ['Emergency_Contact', 'emergency_contact']);
    setFirst('Vehicle_Type', ['Vehicle_Type', 'vehicle_type']);
    setFirst('Vehicle_Number', [
      'Vehicle_Number',
      'Vehicle_No',
      'vehicle_number',
    ]);
    setFirst('Driver_Licence_No', ['Driver_Licence_No', 'driving_license']);
    setFirst('Profile_Photo_Url', ['Profile_Photo_Url', 'profile_photo_url']);

    final email = payload['email'];
    if (email is String) payload['email'] = email.toLowerCase();

    return payload;
  }

  Future<Map<String, dynamic>?> _selectRiderByCandidates(
    List<MapEntry<String, String>> candidates,
  ) async {
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final response = await _client
            .from(riderTable)
            .select()
            .eq(candidate.key, candidate.value)
            .limit(10);

        final profile = _bestRiderProfile(response);
        if (profile != null) return profile;
      } catch (error) {
        if (_isMissingFilterColumn(error, candidate.key)) {
          lastError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastError != null && candidates.length == 1) throw lastError;
    return null;
  }

  Map<String, dynamic>? _bestRiderProfile(dynamic response) {
    if (response is! List || response.isEmpty) return null;

    Map<String, dynamic>? bestProfile;
    var bestScore = -1;
    for (final row in response) {
      if (row is! Map) continue;
      final profile = Map<String, dynamic>.from(row);
      final score = _profileCompletenessScore(profile);
      if (score > bestScore) {
        bestScore = score;
        bestProfile = profile;
      }
    }
    return bestProfile;
  }

  int _profileCompletenessScore(Map<String, dynamic> profile) {
    const keys = [
      'Name',
      'full_name',
      'Phone_Number',
      'phone_number',
      'Branch',
      'branch',
      'NIC',
      'nic_number',
      'Address',
      'home_address',
      'Emergency_Contact',
      'emergency_contact',
      'Vehicle_Type',
      'vehicle_type',
      'Vehicle_Number',
      'Vehicle_No',
      'vehicle_number',
      'Driver_Licence_No',
      'driving_license',
    ];

    var score = 0;
    for (final key in keys) {
      final value = profile[key];
      if (value is String && value.trim().isNotEmpty) score++;
    }
    return score;
  }

  Future<bool> _updateRiderByCandidates(
    List<MapEntry<String, String>> candidates,
    Map<String, dynamic> data, {
    bool insertIfMissing = true,
  }) async {
    final schemaPayload = _riderPayloadForSchema(data);
    final allCandidates = _mergeRiderLookupCandidates([
      ...candidates,
      ..._riderLookupCandidatesFromPayload(schemaPayload),
    ]);

    for (final candidate in allCandidates) {
      var payload = Map<String, dynamic>.from(schemaPayload);

      while (true) {
        try {
          final updatedRows = await _client
              .from(riderTable)
              .update(payload)
              .eq(candidate.key, candidate.value)
              .select();
          if (updatedRows.isNotEmpty) return true;
          break;
        } catch (error) {
          if (_isMissingFilterColumn(error, candidate.key)) {
            break;
          }

          final nextPayload = _withoutMissingColumn(payload, error);
          if (nextPayload == null) {
            break;
          }
          payload = nextPayload;
        }
      }
    }

    if (!insertIfMissing) return false;
    await _insertRider(data);
    return true;
  }

  Future<Map<String, dynamic>?> _updateExistingRiderByCandidates(
    List<MapEntry<String, String>> candidates,
    Map<String, dynamic> data,
  ) async {
    final allCandidates = _mergeRiderLookupCandidates(candidates);

    for (final candidate in allCandidates) {
      var payload = Map<String, dynamic>.from(data);

      while (payload.isNotEmpty) {
        try {
          final updatedRows = await _client
              .from(riderTable)
              .update(payload)
              .eq(candidate.key, candidate.value)
              .select();
          final updatedProfile = _bestRiderProfile(updatedRows);
          if (updatedProfile != null) return updatedProfile;
          break;
        } catch (error) {
          if (_isMissingFilterColumn(error, candidate.key)) break;

          final nextPayload = _withoutMissingColumn(payload, error);
          if (nextPayload == null || nextPayload.isEmpty) rethrow;
          payload = nextPayload;
        }
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _updateBestExistingRiderProfile(
    Map<String, dynamic> data,
  ) async {
    try {
      final rows = await _client.from(riderTable).select().limit(25);
      final profile = _bestRiderProfile(rows);
      final key = _stableKeyFromExistingProfile(profile);
      if (key == null) return null;

      return _updateExistingRiderByCandidates([key], data);
    } catch (error) {
      if (_isMissingTable(error, riderTable)) return null;
      rethrow;
    }
  }

  MapEntry<String, String>? _stableKeyFromExistingProfile(
    Map<String, dynamic>? profile,
  ) {
    if (profile == null) return null;
    return _candidateFromValue('user_id', profile['user_id']) ??
        _candidateFromValue('email', profile['email']) ??
        _candidateFromValue('NIC', profile['NIC']);
  }

  int _compareDeliveriesNewestFirst(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aDate = _deliveryDate(a);
    final bDate = _deliveryDate(b);
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  DateTime? _deliveryDate(Map<String, dynamic> delivery) {
    for (final key in const [
      'created_at',
      'createdAt',
      'created_at_iso',
      'updated_at',
      'updatedAt',
    ]) {
      final value = delivery[key];
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<void> _insertRider(Map<String, dynamic> data) async {
    var payload = _riderPayloadForSchema(data);
    if (!payload.containsKey('NIC')) {
      throw Exception('Please enter NIC number before saving your profile.');
    }

    while (true) {
      try {
        await _client.from(riderTable).insert(payload);
        return;
      } catch (error) {
        if (_isDuplicateKey(error)) {
          await _updateRiderByColumn(
            column: 'NIC',
            value: payload['NIC']?.toString(),
            data: payload,
          );
          return;
        }

        final nextPayload = _withoutMissingColumn(payload, error);
        if (nextPayload == null || nextPayload.isEmpty) rethrow;
        payload = nextPayload;
      }
    }
  }

  Future<void> _updateRiderByColumn({
    required String column,
    required String? value,
    required Map<String, dynamic> data,
  }) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      throw Exception('Cannot update rider without $column.');
    }

    var payload = _riderPayloadForSchema(data);
    while (true) {
      try {
        await _client.from(riderTable).update(payload).eq(column, trimmed);
        return;
      } catch (error) {
        final nextPayload = _withoutMissingColumn(payload, error);
        if (nextPayload == null || nextPayload.isEmpty) rethrow;
        payload = nextPayload;
      }
    }
  }

  List<MapEntry<String, String>> _riderLookupCandidates(
    String userId, {
    String? email,
  }) {
    final candidates = <MapEntry<String, String>>[MapEntry('user_id', userId)];
    final trimmed = email?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      candidates.add(MapEntry('email', trimmed.toLowerCase()));
    }
    return candidates;
  }

  String _profileCacheKey(String userId) => 'rider_profile_$userId';

  Future<String?> _cachedAuthEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastAuthEmailKey);
  }

  Future<void> _cacheAuthEmail(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAuthEmailKey, trimmed);
  }

  Future<Map<String, dynamic>?> _cachedUserProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileCacheKey(userId));
    if (raw == null) return null;

    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_profileCacheKey(userId));
      return null;
    }
  }

  Future<void> _cacheUserProfile(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileCacheKey(userId), jsonEncode(profile));
  }

  List<MapEntry<String, String>> _riderLookupCandidatesFromPayload(
    Map<String, dynamic> payload,
  ) {
    return _mergeRiderLookupCandidates(
      [
        _candidateFromPayload(payload, 'email'),
        _candidateFromPayload(payload, 'NIC'),
      ].whereType<MapEntry<String, String>>().toList(),
    );
  }

  MapEntry<String, String>? _candidateFromPayload(
    Map<String, dynamic> payload,
    String column,
  ) {
    return _candidateFromValue(column, payload[column]);
  }

  MapEntry<String, String>? _candidateFromValue(String column, Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    return MapEntry(
      column,
      column == 'email' ? trimmed.toLowerCase() : trimmed,
    );
  }

  List<MapEntry<String, String>> _mergeRiderLookupCandidates(
    List<MapEntry<String, String>> candidates,
  ) {
    final merged = <MapEntry<String, String>>[];
    final seen = <String>{};

    for (final candidate in candidates) {
      final value = candidate.value.trim();
      if (value.isEmpty) continue;
      final key = '${candidate.key}=$value';
      if (seen.add(key)) merged.add(MapEntry(candidate.key, value));
    }

    return merged;
  }

  String? _missingColumnFrom(Object error) {
    if (error is! PostgrestException || error.code != 'PGRST204') {
      return null;
    }

    final match = RegExp(
      r"Could not find the '([^']+)' column",
    ).firstMatch(error.message);
    return match?.group(1);
  }

  bool _isMissingFilterColumn(Object error, String column) {
    return _isMissingFilterColumnOnTable(error, riderTable, column);
  }

  bool _isMissingFilterColumnOnTable(
    Object error,
    String table,
    String column,
  ) {
    if (error is! PostgrestException || error.code != '42703') {
      return false;
    }

    final message = error.message.toLowerCase();
    final tableName = table.toLowerCase();
    final filterColumn = column.toLowerCase();
    return message.contains('column $tableName.$filterColumn does not exist') ||
        message.contains('column "$tableName"."$filterColumn" does not exist');
  }

  bool _isDuplicateKey(Object error) {
    return error is PostgrestException && error.code == '23505';
  }

  bool _isMissingTable(Object error, String table) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    final tableName = table.toLowerCase();
    return error.code == 'PGRST205' &&
        message.contains('public.$tableName') &&
        message.contains('schema cache');
  }

  String _contentTypeForFile(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
