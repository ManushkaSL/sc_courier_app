import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class PendingRegistrationData {
  const PendingRegistrationData({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    required this.branch,
    required this.nicNumber,
    required this.homeAddress,
    required this.emergencyContact,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.drivingLicense,
    required this.nicFrontImagePath,
    required this.nicBackImagePath,
  });

  final String userId;
  final String email;
  final String fullName;
  final String phoneNumber;
  final String branch;
  final String nicNumber;
  final String homeAddress;
  final String emergencyContact;
  final String vehicleType;
  final String vehicleNumber;
  final String drivingLicense;
  final String nicFrontImagePath;
  final String nicBackImagePath;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'full_name': fullName,
    'phone_number': phoneNumber,
    'branch': branch,
    'nic_number': nicNumber,
    'home_address': homeAddress,
    'emergency_contact': emergencyContact,
    'vehicle_type': vehicleType,
    'vehicle_number': vehicleNumber,
    'driving_license': drivingLicense,
    'nic_front_image_path': nicFrontImagePath,
    'nic_back_image_path': nicBackImagePath,
  };

  factory PendingRegistrationData.fromJson(Map<String, dynamic> json) {
    return PendingRegistrationData(
      userId: json['user_id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      phoneNumber: json['phone_number'] as String,
      branch: json['branch'] as String,
      nicNumber: json['nic_number'] as String,
      homeAddress: json['home_address'] as String,
      emergencyContact: json['emergency_contact'] as String,
      vehicleType: json['vehicle_type'] as String,
      vehicleNumber: json['vehicle_number'] as String,
      drivingLicense: json['driving_license'] as String,
      nicFrontImagePath: json['nic_front_image_path'] as String,
      nicBackImagePath: json['nic_back_image_path'] as String,
    );
  }
}

class PendingRegistrationService {
  static const _storageKey = 'pending_rider_registration';

  /// Saves the pending registration data to shared preferences.
  /// Stores the original image paths directly — no file copying needed.
  static Future<void> save({
    required String userId,
    required String email,
    required String fullName,
    required String phoneNumber,
    required String branch,
    required String nicNumber,
    required String homeAddress,
    required String emergencyContact,
    required String vehicleType,
    required String vehicleNumber,
    required String drivingLicense,
    required String nicFrontSourcePath,
    required String nicBackSourcePath,
  }) async {
    final data = PendingRegistrationData(
      userId: userId,
      email: email.trim().toLowerCase(),
      fullName: fullName,
      phoneNumber: phoneNumber,
      branch: branch,
      nicNumber: nicNumber,
      homeAddress: homeAddress,
      emergencyContact: emergencyContact,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      drivingLicense: drivingLicense,
      nicFrontImagePath: nicFrontSourcePath,
      nicBackImagePath: nicBackSourcePath,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(data.toJson()));
  }

  /// Loads pending registration for the given email, if it exists and
  /// the image files are still accessible on disk.
  static Future<PendingRegistrationData?> loadForEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;

    final data = PendingRegistrationData.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );

    if (data.email != email.trim().toLowerCase()) return null;

    // Image files from image_picker are stored in the app's cache directory
    // and may not persist across sessions — handle gracefully if missing.
    if (!File(data.nicFrontImagePath).existsSync() ||
        !File(data.nicBackImagePath).existsSync()) {
      // Clean up stale record
      await clear();
      return null;
    }

    return data;
  }

  /// Clears the pending registration record from shared preferences.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
