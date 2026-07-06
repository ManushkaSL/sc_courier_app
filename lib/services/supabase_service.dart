import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'pending_registration_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  User? get currentUser => FirebaseAuth.instance.currentUser;

  bool get isAuthenticated => FirebaseAuth.instance.currentUser != null;

  Future<void> initialize() async {}

  // Kept as SupabaseService for existing screens, but Firebase is the backend.

  // Storage
  Future<String> uploadNicImage(Uint8List fileBytes, String fileName) async {
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final ref = _storage.ref().child('NIC_images/$safeFileName');
    final uploadTask = await ref
        .putData(
          fileBytes,
          SettableMetadata(contentType: _contentTypeForFile(safeFileName)),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception(
              'NIC image upload timed out. Check Firebase Storage rules and network connection.',
            );
          },
        );
    return uploadTask.ref.getDownloadURL().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception('Could not get NIC image download URL.');
      },
    );
  }

  // User Profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final doc = await _db.collection('riders').doc(userId).get();
    if (doc.exists) return _withId(doc);

    final snapshot = await _db
        .collection('riders')
        .where('firebase_uid', isEqualTo: userId)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return _withId(snapshot.docs.first);
  }

  Future<void> completeRiderRegistration(PendingRegistrationData data) async {
    final existingProfile = await getUserProfile(data.userId);
    if (existingProfile != null) return;
    // NIC upload temporarily disabled due to issues.
    await createUserProfile(
      userId: data.userId,
      fullName: data.fullName,
      email: data.email,
      phoneNumber: data.phoneNumber,
      branch: data.branch,
      nicNumber: data.nicNumber,
      homeAddress: data.homeAddress,
      emergencyContact: data.emergencyContact,
      vehicleType: data.vehicleType,
      vehicleNumber: data.vehicleNumber,
      drivingLicense: data.drivingLicense,
      nicFrontImageUrl: null,
      nicBackImageUrl: null,
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
    final profile = <String, dynamic>{
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
      'created_at': FieldValue.serverTimestamp(),
    };

    await _db.collection('riders').doc(userId).set(profile);
    return {...profile, 'id': userId};
  }

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    await _db
        .collection('riders')
        .doc(userId)
        .set(updates, SetOptions(merge: true));
  }

  // Deliveries
  Future<List<Map<String, dynamic>>> getDeliveries({String? status}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Query<Map<String, dynamic>> query = _db.collection('deliveries');

    if (uid != null) {
      query = query.where('rider_id', isEqualTo: uid);
    }

    final snapshot = await query.get();
    final deliveries = snapshot.docs.map(_withId).where((delivery) {
      return status == null || delivery['status'] == status;
    }).toList();

    deliveries.sort(
      (a, b) => _createdAtMillis(b).compareTo(_createdAtMillis(a)),
    );
    return deliveries;
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
    final doc = _db.collection('deliveries').doc();
    final delivery = <String, dynamic>{
      'tracking_code': doc.id,
      'parcel_id': doc.id,
      'rider_id': FirebaseAuth.instance.currentUser?.uid,
      'pickup_address': pickupAddress,
      'delivery_address': deliveryAddress,
      'distance': distance,
      'price': price,
      'package_description': packageDescription,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'status': 'pending',
      'live_tracking_enabled': true,
      'created_at': FieldValue.serverTimestamp(),
      'created_at_iso': DateTime.now().toIso8601String(),
    };

    await doc.set(delivery);
    return {...delivery, 'id': doc.id};
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    await _db.collection('deliveries').doc(deliveryId).update({
      'status': status,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getDeliveryById(String deliveryId) async {
    final doc = await _db.collection('deliveries').doc(deliveryId).get();
    if (!doc.exists) return null;
    return _withId(doc);
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
      'avatar_url': null,
    };
  }

  Map<String, dynamic> _withId(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return {...data, 'id': doc.id};
  }

  int _createdAtMillis(Map<String, dynamic> data) {
    final createdAt = data['created_at'];
    if (createdAt is Timestamp) return createdAt.millisecondsSinceEpoch;
    if (createdAt is String) {
      return DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ?? 0;
    }

    final createdAtIso = data['created_at_iso'];
    if (createdAtIso is String) {
      return DateTime.tryParse(createdAtIso)?.millisecondsSinceEpoch ?? 0;
    }

    return 0;
  }

  String _contentTypeForFile(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
