import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/firestore_service.dart';
import '../utils/validators.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  static const String routeName = '/profile_settings';

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _firestoreService = FirestoreService();
  final _profileFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _branchController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _licenseController = TextEditingController();
  final _picker = ImagePicker();

  String? _vehicleType;
  String? _profilePhotoUrl;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoName;
  bool _isProfileLoading = true;
  bool _isProfileSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _branchController.dispose();
    _addressController.dispose();
    _emergencyController.dispose();
    _vehicleNumberController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isProfileLoading = false);
      return;
    }

    try {
      final profile = await _firestoreService.getRiderByUid(user.uid);
      if (!mounted) return;
      setState(() {
        _nameController.text = _profileValue(profile, ['Name', 'full_name']);
        _phoneController.text = _profileValue(profile, [
          'Phone_Number',
          'phone_number',
        ]);
        _branchController.text = _profileValue(profile, ['Branch', 'branch']);
        _addressController.text = _profileValue(profile, [
          'Address',
          'address',
        ]);
        _emergencyController.text = _profileValue(profile, [
          'Emergency_Contact',
          'emergency_contact',
        ]);
        _vehicleType = _profileValue(profile, ['Vehicle_Type', 'vehicle_type']);
        if (_vehicleType != 'Bike' &&
            _vehicleType != 'Three Wheeler' &&
            _vehicleType != 'Van') {
          _vehicleType = null;
        }
        _vehicleNumberController.text = _profileValue(profile, [
          'Vehicle_No',
          'vehicle_number',
        ]);
        _licenseController.text = _profileValue(profile, [
          'Driver_Licence_No',
          'driving_license',
        ]);
        _profilePhotoUrl = _profileValue(profile, [
          'Profile_Photo_Url',
          'profile_photo_url',
        ]);
        _isProfileLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProfileLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load profile: $e')));
    }
  }

  String _profileValue(Map<String, dynamic>? profile, List<String> keys) {
    if (profile == null) return '';
    for (final key in keys) {
      final value = profile[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Future<void> _pickProfilePhoto() async {
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1200,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selectedPhotoBytes = bytes;
      _selectedPhotoName = photo.name;
    });
  }

  Future<String?> _uploadSelectedPhoto(String riderId) async {
    final bytes = _selectedPhotoBytes;
    if (bytes == null) return _profilePhotoUrl;

    final safeName = (_selectedPhotoName ?? 'profile.jpg').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance
        .ref()
        .child('rider_profiles')
        .child(riderId)
        .child(fileName);

    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> _saveProfile() async {
    final formState = _profileFormKey.currentState;
    if (formState == null || !formState.validate() || _isProfileSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isProfileSaving = true);

    try {
      final photoUrl = await _uploadSelectedPhoto(user.uid);
      await _firestoreService.updateRiderProfile(
        riderId: user.uid,
        data: {
          'Name': _nameController.text.trim(),
          'Phone_Number': _phoneController.text.trim(),
          'Branch': _branchController.text.trim(),
          'Address': _addressController.text.trim(),
          'Emergency_Contact': _emergencyController.text.trim(),
          'Vehicle_Type': _vehicleType,
          'Vehicle_No': _vehicleNumberController.text.trim(),
          'Driver_Licence_No': _licenseController.text.trim(),
          'Profile_Photo_Url': photoUrl,
          'profile_photo_url': photoUrl,
          'profile_completed_at': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;
      setState(() {
        _profilePhotoUrl = photoUrl;
        _selectedPhotoBytes = null;
        _selectedPhotoName = null;
        _isProfileSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile settings saved successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProfileSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save profile: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A1A), Color(0xFF212121), Color(0xFF1A1A1A)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _ProfileSettingsCard(
              formKey: _profileFormKey,
              isLoading: _isProfileLoading,
              isSaving: _isProfileSaving,
              selectedPhotoBytes: _selectedPhotoBytes,
              profilePhotoUrl: _profilePhotoUrl,
              nameController: _nameController,
              phoneController: _phoneController,
              branchController: _branchController,
              addressController: _addressController,
              emergencyController: _emergencyController,
              vehicleNumberController: _vehicleNumberController,
              licenseController: _licenseController,
              vehicleType: _vehicleType,
              onVehicleTypeChanged: (value) =>
                  setState(() => _vehicleType = value),
              onPickPhoto: _pickProfilePhoto,
              onSave: _saveProfile,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSettingsCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final bool isSaving;
  final Uint8List? selectedPhotoBytes;
  final String? profilePhotoUrl;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController branchController;
  final TextEditingController addressController;
  final TextEditingController emergencyController;
  final TextEditingController vehicleNumberController;
  final TextEditingController licenseController;
  final String? vehicleType;
  final ValueChanged<String?> onVehicleTypeChanged;
  final VoidCallback onPickPhoto;
  final VoidCallback onSave;

  const _ProfileSettingsCard({
    required this.formKey,
    required this.isLoading,
    required this.isSaving,
    required this.selectedPhotoBytes,
    required this.profilePhotoUrl,
    required this.nameController,
    required this.phoneController,
    required this.branchController,
    required this.addressController,
    required this.emergencyController,
    required this.vehicleNumberController,
    required this.licenseController,
    required this.vehicleType,
    required this.onVehicleTypeChanged,
    required this.onPickPhoto,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = profilePhotoUrl;
    final ImageProvider? avatarImage = selectedPhotoBytes != null
        ? MemoryImage(selectedPhotoBytes!)
        : photoUrl != null && photoUrl.isNotEmpty
        ? NetworkImage(photoUrl)
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFF97316)),
                  ),
                )
              : Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 38,
                                backgroundColor: const Color(
                                  0xFFF97316,
                                ).withValues(alpha: 0.16),
                                backgroundImage: avatarImage,
                                child: avatarImage == null
                                    ? const Icon(
                                        Icons.person,
                                        color: Color(0xFFF97316),
                                        size: 36,
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: onPickPhoto,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF97316),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF222222),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rider Profile',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Update contact, emergency, and vehicle details.',
                                  style: TextStyle(
                                    color: Color(0xFFAAAAAA),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _ProfileField(
                        controller: nameController,
                        label: 'Full Name',
                        icon: Icons.person_outline,
                        validator: Validators.validateName,
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        controller: phoneController,
                        label: 'Phone Number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: Validators.validatePhoneNumber,
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        controller: branchController,
                        label: 'Branch',
                        icon: Icons.store_outlined,
                        validator: (value) =>
                            Validators.validateRequired(value, 'Branch'),
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        controller: addressController,
                        label: 'Home Address',
                        icon: Icons.home_outlined,
                        minLines: 2,
                        maxLines: 3,
                        validator: (value) =>
                            Validators.validateRequired(value, 'Home Address'),
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        controller: emergencyController,
                        label: 'Emergency Contact',
                        icon: Icons.emergency_outlined,
                        keyboardType: TextInputType.phone,
                        validator: Validators.validatePhoneNumber,
                      ),
                      const SizedBox(height: 18),
                      Divider(color: Colors.white.withValues(alpha: 0.08)),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        initialValue: vehicleType,
                        dropdownColor: const Color(0xFF232323),
                        style: const TextStyle(color: Colors.white),
                        decoration: _profileInputDecoration(
                          label: 'Vehicle Type',
                          icon: Icons.directions_bike_outlined,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Bike', child: Text('Bike')),
                          DropdownMenuItem(
                            value: 'Three Wheeler',
                            child: Text('Three Wheeler'),
                          ),
                          DropdownMenuItem(value: 'Van', child: Text('Van')),
                        ],
                        onChanged: onVehicleTypeChanged,
                        validator: (value) =>
                            value == null ? 'Please select vehicle type' : null,
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        controller: vehicleNumberController,
                        label: 'Vehicle Number',
                        icon: Icons.pin_outlined,
                        validator: Validators.validateVehicleNumber,
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        controller: licenseController,
                        label: 'Driving License Number',
                        icon: Icons.article_outlined,
                        validator: (value) => Validators.validateRequired(
                          value,
                          'Driving License Number',
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: isSaving ? null : onSave,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            isSaving ? 'Saving...' : 'Save Profile Settings',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final String? Function(String?)? validator;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.minLines,
    this.maxLines,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines ?? 1,
      style: const TextStyle(color: Colors.white),
      decoration: _profileInputDecoration(label: label, icon: icon),
      validator: validator,
    );
  }
}

InputDecoration _profileInputDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: const Color(0xFFF97316), size: 20),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFF97316), width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
    ),
    labelStyle: const TextStyle(color: Color(0xFFBBBBBB)),
    errorStyle: const TextStyle(color: Colors.redAccent),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  );
}
