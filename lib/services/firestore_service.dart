import 'rider_service.dart';

@Deprecated('Use RiderService. This wrapper remains for older imports.')
class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final _riderService = RiderService();

  Future<void> saveRider(Map<String, dynamic> riderData) {
    return _riderService.saveRider(riderData);
  }

  Future<Map<String, dynamic>?> getRiderByUid(String uid) {
    return _riderService.getRiderByUid(uid);
  }

  Future<void> updateRiderProfile({
    required String riderId,
    required Map<String, dynamic> data,
  }) {
    return _riderService.updateRiderProfile(riderId: riderId, data: data);
  }

  Future<void> updateRiderLiveLocation({
    required String riderId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
  }) {
    return _riderService.updateRiderLiveLocation(
      riderId: riderId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
    );
  }

  Future<void> markRiderLocationOffline(String riderId) {
    return _riderService.markRiderLocationOffline(riderId);
  }
}
