import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/rider_service.dart';
import '../services/supabase_service.dart';
import '../utils/validators.dart';

const _brandOrange = Color(0xFFF97316);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _surfaceSoft = Color(0xFF2A2A2A);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  static const String routeName = '/profile_settings';

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _riderService = RiderService();
  final _supabaseService = SupabaseService();
  final _profileFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _branchController = TextEditingController();
  final _nicController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _licenseController = TextEditingController();
  final _picker = ImagePicker();

  String? _vehicleType;
  String? _profilePhotoUrl;
  String? _loadedProfileUserId;
  String? _loadedProfileEmail;
  String? _loadedProfileNic;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoName;
  bool _profilePhotoUploadSkipped = false;
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
    _nicController.dispose();
    _addressController.dispose();
    _emergencyController.dispose();
    _vehicleNumberController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _supabaseService.currentUserOrRestored();
      final profile = user == null
          ? await _supabaseService.getCurrentRiderProfile()
          : await _riderService.getRiderByUid(user.id);
      if (!mounted) return;
      setState(() {
        _nameController.text = _profileValue(profile, ['Name', 'full_name']);
        _phoneController.text = _profileValue(profile, [
          'Phone_Number',
          'phone_number',
        ]);
        _branchController.text = _profileValue(profile, ['Branch', 'branch']);
        _nicController.text = _profileValue(profile, ['NIC', 'nic_number']);
        _loadedProfileUserId = _profileValue(profile, [
          'user_id',
          'id',
          'firebase_uid',
        ]);
        _loadedProfileEmail = _profileValue(profile, ['email', 'Email']);
        _loadedProfileNic = _nicController.text;
        _addressController.text = _profileValue(profile, [
          'Address',
          'home_address',
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
          'Vehicle_Number',
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
    try {
      return await _supabaseService.uploadRiderProfilePhoto(
        riderId: riderId,
        fileBytes: bytes,
        fileName: safeName,
      );
    } catch (error) {
      if (!_isMissingStorageBucket(error)) rethrow;
      _profilePhotoUploadSkipped = true;
      return _profilePhotoUrl;
    }
  }

  bool _isMissingStorageBucket(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('bucket not found') ||
        message.contains('storageexception') && message.contains('404');
  }

  Future<void> _saveProfile() async {
    final formState = _profileFormKey.currentState;
    if (_isProfileSaving) return;
    if (formState == null || !formState.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the highlighted fields.')),
      );
      return;
    }

    final user = _supabaseService.currentUser;
    if (user == null) return;

    setState(() => _isProfileSaving = true);
    _profilePhotoUploadSkipped = false;

    try {
      final photoUrl = await _uploadSelectedPhoto(user.id);
      final now = DateTime.now().toIso8601String();
      final updatedProfile = <String, dynamic>{
        'id': user.id,
        'user_id': user.id,
        'firebase_uid': user.id,
        if (user.email != null && user.email!.trim().isNotEmpty)
          'email': user.email!.trim(),
        if (_loadedProfileUserId != null &&
            _loadedProfileUserId!.trim().isNotEmpty)
          'original_user_id': _loadedProfileUserId!.trim(),
        if (_loadedProfileEmail != null &&
            _loadedProfileEmail!.trim().isNotEmpty)
          'original_email': _loadedProfileEmail!.trim(),
        if (_loadedProfileNic != null && _loadedProfileNic!.trim().isNotEmpty)
          'original_NIC': _loadedProfileNic!.trim(),
        'full_name': _nameController.text.trim(),
        'Name': _nameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'Phone_Number': _phoneController.text.trim(),
        'branch': _branchController.text.trim(),
        'Branch': _branchController.text.trim(),
        'nic_number': _nicController.text.trim(),
        'NIC': _nicController.text.trim(),
        'home_address': _addressController.text.trim(),
        'Address': _addressController.text.trim(),
        'emergency_contact': _emergencyController.text.trim(),
        'Emergency_Contact': _emergencyController.text.trim(),
        'vehicle_type': _vehicleType,
        'Vehicle_Type': _vehicleType,
        'Vehicle_Number': _vehicleNumberController.text.trim(),
        'vehicle_number': _vehicleNumberController.text.trim(),
        'Vehicle_No': _vehicleNumberController.text.trim(),
        'driving_license': _licenseController.text.trim(),
        'Driver_Licence_No': _licenseController.text.trim(),
        if (photoUrl != null && photoUrl.trim().isNotEmpty) ...{
          'profile_photo_url': photoUrl.trim(),
          'Profile_Photo_Url': photoUrl.trim(),
        },
        'profile_completed_at': now,
        'updated_at': now,
      };

      await _riderService.updateRiderProfile(
        riderId: user.id,
        data: updatedProfile,
      );

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/settings',
        (route) => route.settings.name == '/dashboard',
        arguments: {
          'profileSaved': true,
          'photoUploadSkipped': _profilePhotoUploadSkipped,
        },
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
      backgroundColor: _appBg,
      appBar: AppBar(
        backgroundColor: _appBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _ProfileSettingsContent(
          formKey: _profileFormKey,
          isLoading: _isProfileLoading,
          selectedPhotoBytes: _selectedPhotoBytes,
          profilePhotoUrl: _profilePhotoUrl,
          nameController: _nameController,
          phoneController: _phoneController,
          branchController: _branchController,
          nicController: _nicController,
          addressController: _addressController,
          emergencyController: _emergencyController,
          vehicleNumberController: _vehicleNumberController,
          licenseController: _licenseController,
          vehicleType: _vehicleType,
          onVehicleTypeChanged: (value) =>
              setState(() => _vehicleType = value),
          onPickPhoto: _pickProfilePhoto,
        ),
      ),
      bottomNavigationBar: _isProfileLoading
          ? null
          : _SaveProfileBar(isSaving: _isProfileSaving, onSave: _saveProfile),
    );
  }
}

class _ProfileSettingsContent extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final Uint8List? selectedPhotoBytes;
  final String? profilePhotoUrl;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController branchController;
  final TextEditingController nicController;
  final TextEditingController addressController;
  final TextEditingController emergencyController;
  final TextEditingController vehicleNumberController;
  final TextEditingController licenseController;
  final String? vehicleType;
  final ValueChanged<String?> onVehicleTypeChanged;
  final VoidCallback onPickPhoto;

  const _ProfileSettingsContent({
    required this.formKey,
    required this.isLoading,
    required this.selectedPhotoBytes,
    required this.profilePhotoUrl,
    required this.nameController,
    required this.phoneController,
    required this.branchController,
    required this.nicController,
    required this.addressController,
    required this.emergencyController,
    required this.vehicleNumberController,
    required this.licenseController,
    required this.vehicleType,
    required this.onVehicleTypeChanged,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _brandOrange),
      );
    }

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
        children: [
          _ProfileHeader(
            selectedPhotoBytes: selectedPhotoBytes,
            profilePhotoUrl: profilePhotoUrl,
            onPickPhoto: onPickPhoto,
          ),
          const SizedBox(height: 22),
          _FormSection(
            title: 'Personal',
            children: [
              _ProfileField(
                controller: nameController,
                label: 'Full Name',
                validator: Validators.validateName,
              ),
              _ProfileField(
                controller: branchController,
                label: 'Branch',
                validator: (value) =>
                    Validators.validateRequired(value, 'Branch'),
              ),
              _ProfileField(
                controller: nicController,
                label: 'NIC Number',
                validator: Validators.validateNIC,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _FormSection(
            title: 'Contact',
            children: [
              _ProfileField(
                controller: phoneController,
                label: 'Phone Number',
                keyboardType: TextInputType.phone,
                validator: Validators.validatePhoneNumber,
              ),
              _ProfileField(
                controller: addressController,
                label: 'Home Address',
                minLines: 2,
                maxLines: 3,
                validator: (value) =>
                    Validators.validateRequired(value, 'Home Address'),
              ),
              _ProfileField(
                controller: emergencyController,
                label: 'Emergency Contact',
                keyboardType: TextInputType.phone,
                validator: Validators.validatePhoneNumber,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _FormSection(
            title: 'Vehicle',
            children: [
              _VehicleTypeField(
                vehicleType: vehicleType,
                onChanged: onVehicleTypeChanged,
              ),
              _ProfileField(
                controller: vehicleNumberController,
                label: 'Vehicle Number',
                validator: Validators.validateVehicleNumber,
              ),
              _ProfileField(
                controller: licenseController,
                label: 'Driving License Number',
                validator: (value) => Validators.validateRequired(
                  value,
                  'Driving License Number',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Uint8List? selectedPhotoBytes;
  final String? profilePhotoUrl;
  final VoidCallback onPickPhoto;

  const _ProfileHeader({
    required this.selectedPhotoBytes,
    required this.profilePhotoUrl,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = profilePhotoUrl;
    final ImageProvider? avatarImage = selectedPhotoBytes != null
        ? MemoryImage(selectedPhotoBytes!)
        : photoUrl != null && photoUrl.isNotEmpty
        ? NetworkImage(photoUrl)
        : null;

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: _brandOrange.withValues(alpha: 0.14),
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? const Icon(Icons.person, color: _brandOrange, size: 34)
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Material(
                color: _brandOrange,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPickPhoto,
                  child: const SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
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
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Keep your delivery contact and vehicle details current.',
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FormSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _SurfacePanel(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final String? Function(String?)? validator;

  const _ProfileField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.minLines,
    this.maxLines,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            minLines: minLines,
            maxLines: maxLines ?? 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: _profileInputDecoration(hint: label),
            validator: validator,
          ),
        ],
      ),
    );
  }
}

class _VehicleTypeField extends StatelessWidget {
  final String? vehicleType;
  final ValueChanged<String?> onChanged;

  const _VehicleTypeField({
    required this.vehicleType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('Vehicle Type'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: vehicleType,
            dropdownColor: _surface,
            iconEnabledColor: _textMuted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: _profileInputDecoration(hint: 'Vehicle Type'),
            items: const [
              DropdownMenuItem(value: 'Bike', child: Text('Bike')),
              DropdownMenuItem(
                value: 'Three Wheeler',
                child: Text('Three Wheeler'),
              ),
              DropdownMenuItem(value: 'Van', child: Text('Van')),
            ],
            onChanged: onChanged,
            validator: (value) =>
                value == null ? 'Please select vehicle type' : null,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;

  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SaveProfileBar extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onSave;

  const _SaveProfileBar({required this.isSaving, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        decoration: const BoxDecoration(
          color: _appBg,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
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
            label: Text(isSaving ? 'Saving...' : 'Save Changes'),
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _brandOrange.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SurfacePanel({
    required this.child,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      padding: padding,
      child: child,
    );
  }
}

InputDecoration _profileInputDecoration({required String hint}) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: _surfaceSoft,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _brandOrange, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
    ),
    hintStyle: const TextStyle(color: Color(0xFF777777)),
    errorStyle: const TextStyle(color: Colors.redAccent),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  );
}
