import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> liveDeliveryStatuses = [
    'pending',
    'accepted',
    'picked_up',
    'in_transit',
    'out_for_delivery',
  ];

  Future<void> saveRider(Map<String, dynamic> riderData) async {
    // Prefer using firebase_uid as the document ID for easy security rules
    final firebaseUid = (riderData['firebase_uid'] as String?)?.trim();
    if (firebaseUid != null && firebaseUid.isNotEmpty) {
      await _db
          .collection('riders')
          .doc(firebaseUid)
          .set(riderData)
          .timeout(const Duration(seconds: 20));
      return;
    }

    // Fallback to NIC or auto-generated ID
    final nicId = (riderData['NIC'] as String?)?.trim();
    if (nicId != null && nicId.isNotEmpty) {
      await _db
          .collection('riders')
          .doc(nicId)
          .set(riderData)
          .timeout(const Duration(seconds: 20));
      return;
    }

    await _db
        .collection('riders')
        .add(riderData)
        .timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>?> getRiderByUid(String uid) async {
    final uidDoc = await _db.collection('riders').doc(uid).get();
    if (uidDoc.exists) return _withId(uidDoc);

    final snapshot = await _db
        .collection('riders')
        .where('firebase_uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    final data = doc.data();
    data['id'] = doc.id;
    return data;
  }

  Future<void> updateRiderLiveLocation({
    required String riderId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
  }) async {
    final location = <String, dynamic>{
      'rider_id': riderId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'is_online': true,
      'updated_at': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(
      _db.collection('riderLocations').doc(riderId),
      location,
      SetOptions(merge: true),
    );
    batch.set(_db.collection('riders').doc(riderId), {
      'firebase_uid': riderId,
      'live_location': location,
      'is_tracking': true,
      'last_location_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final deliveries = await _db
        .collection('deliveries')
        .where('rider_id', isEqualTo: riderId)
        .where('status', whereIn: liveDeliveryStatuses)
        .get();

    for (final doc in deliveries.docs) {
      batch.set(doc.reference, {
        'rider_live_location': location,
        'rider_location_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit().timeout(const Duration(seconds: 20));
  }

  Future<void> markRiderLocationOffline(String riderId) async {
    final offlineData = {
      'rider_id': riderId,
      'is_online': false,
      'stopped_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(
      _db.collection('riderLocations').doc(riderId),
      offlineData,
      SetOptions(merge: true),
    );
    batch.set(_db.collection('riders').doc(riderId), {
      'firebase_uid': riderId,
      'is_tracking': false,
      'last_location_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final deliveries = await _db
        .collection('deliveries')
        .where('rider_id', isEqualTo: riderId)
        .where('status', whereIn: liveDeliveryStatuses)
        .get();

    for (final doc in deliveries.docs) {
      batch.set(doc.reference, {
        'rider_live_location': {'is_online': false},
        'rider_location_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit().timeout(const Duration(seconds: 20));
  }

  Map<String, dynamic> _withId(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return {...data, 'id': doc.id};
  }
}
