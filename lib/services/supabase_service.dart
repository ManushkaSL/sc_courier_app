import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  late final SupabaseClient _client;

  SupabaseClient get client => _client;
  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => _client.auth.currentUser != null;

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://lzoxjmevvjycclfwjtks.supabase.co',
      anonKey: 'sb_publishable_mQt-t-8nWjJ7Bya_EVdkaA_QhZr80qu',
    );
    _client = Supabase.instance.client;
  }

  // Authentication
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // User Profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return response;
  }

  Future<Map<String, dynamic>> createUserProfile({
    required String userId,
    required String fullName,
    required String email,
    String? phoneNumber,
    String? vehicleType,
    String? vehicleNumber,
  }) async {
    final response = await _client
        .from('users')
        .insert({
          'id': userId,
          'full_name': fullName,
          'email': email,
          'phone_number': phoneNumber,
          'vehicle_type': vehicleType,
          'vehicle_number': vehicleNumber,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();
    return response;
  }

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    await _client.from('users').update(updates).eq('id', userId);
  }

  // Deliveries
  Future<List<Map<String, dynamic>>> getDeliveries({String? status}) async {
    var query = _client.from('deliveries').select();

    if (status != null) {
      query = query.eq('status', status);
    }

    final response = await query.order('created_at', ascending: false);
    return response;
  }

  Future<Map<String, dynamic>> createDelivery({
    required String pickupAddress,
    required String deliveryAddress,
    required double distance,
    required double price,
    String? packageDescription,
    String? recipientName,
    String? recipientPhone,
  }) async {
    final response = await _client
        .from('deliveries')
        .insert({
          'rider_id': currentUser?.id,
          'pickup_address': pickupAddress,
          'delivery_address': deliveryAddress,
          'distance': distance,
          'price': price,
          'package_description': packageDescription,
          'recipient_name': recipientName,
          'recipient_phone': recipientPhone,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();
    return response;
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    await _client
        .from('deliveries')
        .update({'status': status})
        .eq('id', deliveryId);
  }

  Future<Map<String, dynamic>?> getDeliveryById(String deliveryId) async {
    final response = await _client
        .from('deliveries')
        .select()
        .eq('id', deliveryId)
        .maybeSingle();
    return response;
  }

  // Statistics
  Future<Map<String, dynamic>> getRiderStats(String userId) async {
    final deliveries = await getDeliveries();

    final completed = deliveries
        .where((d) => d['status'] == 'completed')
        .length;
    final pending = deliveries.where((d) => d['status'] == 'pending').length;
    final totalEarnings = deliveries
        .where((d) => d['status'] == 'completed')
        .fold<double>(0, (sum, d) => sum + (d['price'] as num).toDouble());

    return {
      'completed': completed,
      'pending': pending,
      'total_earnings': totalEarnings,
      'avatar_url': null, // Can update once files are handled
    };
  }
}
