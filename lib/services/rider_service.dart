import 'supabase_service.dart';

class RiderService {
  static final RiderService _instance = RiderService._internal();
  factory RiderService() => _instance;
  RiderService._internal();

  final _supabaseService = SupabaseService();

  Future<void> saveRider(Map<String, dynamic> riderData) {
    return _supabaseService.saveRider(riderData);
  }

  Future<Map<String, dynamic>?> getRiderByUid(String uid) {
    return _supabaseService.getRiderByUid(uid);
  }

  Future<void> updateRiderProfile({
    required String riderId,
    required Map<String, dynamic> data,
  }) {
    return _supabaseService.updateRiderProfile(riderId: riderId, data: data);
  }

  Future<void> updateRiderLiveLocation({
    required String riderId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
  }) {
    return _supabaseService.updateRiderLiveLocation(
      riderId: riderId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
    );
  }

  Future<void> markRiderLocationOffline(String riderId) {
    return _supabaseService.markRiderLocationOffline(riderId);
  }
}
