import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/rider_service.dart';
import '../services/supabase_service.dart';
import '../utils/validators.dart';
import '../widgets/loading_overlay.dart';
import 'dashboard_screen.dart';

const _brandOrange = Color(0xFFF97316);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _surfaceSoft = Color(0xFF2A2A2A);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const String routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _supabaseService = SupabaseService();

  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final TextEditingController _nicNumberController = TextEditingController();
  final TextEditingController _homeAddressController = TextEditingController();
  final TextEditingController _emergencyContactController =
      TextEditingController();

  final TextEditingController _vehicleNumberController =
      TextEditingController();
  final TextEditingController _drivingLicenseController =
      TextEditingController();

  String? _vehicleType;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneNumberController.dispose();
    _branchController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicNumberController.dispose();
    _homeAddressController.dispose();
    _emergencyContactController.dispose();
    _vehicleNumberController.dispose();
    _drivingLicenseController.dispose();
    super.dispose();
  }

  bool _validateCurrentStep() {
    final formState = _formKey.currentState;
    if (formState == null) return false;
    if (!formState.validate()) return false;

    if (_currentStep == 2 && _vehicleType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select vehicle type.')),
      );
      return false;
    }

    return true;
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_currentStep < 2) {
      setState(() => _currentStep += 1);
    }
  }

  void _backStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  void _handleRegister() async {
    if (!_validateCurrentStep()) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);

    User? createdUser;

    try {
      final cred = await _supabaseService
          .signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          )
          .timeout(const Duration(seconds: 30));

      final userId = cred.user?.id;
      if (userId == null) {
        throw Exception('Could not create Supabase user.');
      }
      createdUser = cred.user;

      final nic = _nicNumberController.text.trim();
      final frontUrl = null;
      final backUrl = null;

      final riderPayload = <String, dynamic>{
        'id': userId,
        'user_id': userId,
        'firebase_uid': userId,
        'full_name': _fullNameController.text.trim(),
        'NIC': nic,
        'nic_number': nic,
        'Name': _fullNameController.text.trim(),
        'phone_number': _phoneNumberController.text.trim(),
        'Phone_Number': _phoneNumberController.text.trim(),
        'branch': _branchController.text.trim(),
        'Branch': _branchController.text.trim(),
        'email': _emailController.text.trim(),
        'Email': _emailController.text.trim(),
        'NIC_Front_Image': frontUrl,
        'nic_front_image': frontUrl,
        'NIC_Back_Image': backUrl,
        'nic_back_image': backUrl,
        'home_address': _homeAddressController.text.trim(),
        'Address': _homeAddressController.text.trim(),
        'emergency_contact': _emergencyContactController.text.trim(),
        'Emergency_Contact': _emergencyContactController.text.trim(),
        'vehicle_type': _vehicleType,
        'Vehicle_Type': _vehicleType,
        'vehicle_number': _vehicleNumberController.text.trim(),
        'Vehicle_No': _vehicleNumberController.text.trim(),
        'driving_license': _drivingLicenseController.text.trim(),
        'Driver_Licence_No': _drivingLicenseController.text.trim(),
        'created_at_iso': DateTime.now().toIso8601String(),
      };

      await RiderService().saveRider(riderPayload);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        DashboardScreen.routeName,
        (_) => false,
      );
    } catch (e) {
      final authUser = _supabaseService.currentUser;
      if (createdUser != null && authUser?.id == createdUser.id) {
        try {
          await _supabaseService.deleteCurrentUser();
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _isLoading = false);

        final errorMessage = _registrationErrorMessage(e);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String _registrationErrorMessage(Object error) {
    if (error is TimeoutException || error.toString().contains('timed out')) {
      return 'Registration is taking too long. Please try again or check Supabase policies.';
    }

    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('already')) {
        return 'This email is already registered. Try logging in or use a different email.';
      }
      if (message.contains('invalid email')) {
        return 'Invalid email format. Please check your email address.';
      }
      if (message.contains('password')) {
        return 'Password must be at least 6 characters.';
      }
      if (message.contains('rate') || message.contains('too many')) {
        return 'Too many registration attempts. Please wait a few minutes and try again.';
      }
      return error.message;
    }

    if (error is PostgrestException) {
      if (error.code == '42501' || error.message.contains('permission')) {
        return 'Supabase permission denied. Check table RLS policies and try again.';
      }
      return 'Supabase database error: ${error.message}';
    }

    final rawMessage = error.toString();
    if (rawMessage.contains('permission-denied') ||
        rawMessage.contains('unauthorized') ||
        rawMessage.contains('403')) {
      return 'Supabase permission denied. Check table/storage RLS policies and try again.';
    }

    return 'Registration failed: $rawMessage';
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['Account', 'Personal', 'Vehicle'];
    final stepSubtitles = [
      'Create your rider login.',
      'Add identity and contact details.',
      'Add your delivery vehicle details.',
    ];

    return Scaffold(
      backgroundColor: _appBg,
      appBar: AppBar(
        backgroundColor: _appBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 24, width: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'SC Courier Rider App',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AuthHeader(
                        title: 'Register',
                        subtitle: 'Set up your rider account.',
                      ),
                      const SizedBox(height: 18),
                      _StepHeader(
                        currentStep: _currentStep,
                        title: stepTitles[_currentStep],
                        subtitle: stepSubtitles[_currentStep],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    children: [
                      _SurfacePanel(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: _currentStepContent(),
                      ),
                    ],
                  ),
                ),
                _RegisterActions(
                  currentStep: _currentStep,
                  onBack: _currentStep == 0 ? null : _backStep,
                  onNext: _currentStep == 2 ? _handleRegister : _nextStep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentStepContent() {
    if (_currentStep == 0) {
      return Column(
        children: [
          _AuthField(
            controller: _fullNameController,
            label: 'Full Name',
            validator: Validators.validateName,
          ),
          _AuthField(
            controller: _phoneNumberController,
            label: 'Phone Number',
            keyboardType: TextInputType.phone,
            validator: Validators.validatePhoneNumber,
          ),
          _AuthField(
            controller: _branchController,
            label: 'Branch',
            validator: (v) => Validators.validateRequired(v, 'Branch'),
          ),
          _AuthField(
            controller: _emailController,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            validator: Validators.validateEmail,
          ),
          _AuthField(
            controller: _passwordController,
            label: 'Password',
            obscureText: _obscurePassword,
            validator: Validators.validatePassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _textMuted,
              ),
            ),
          ),
          _AuthField(
            controller: _confirmPasswordController,
            label: 'Confirm Password',
            obscureText: _obscureConfirmPassword,
            validator: (v) => Validators.validatePasswordMatch(
              v,
              _passwordController.text,
            ),
            suffixIcon: IconButton(
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _textMuted,
              ),
            ),
          ),
        ],
      );
    }

    if (_currentStep == 1) {
      return Column(
        children: [
          _AuthField(
            controller: _nicNumberController,
            label: 'NIC Number',
            validator: Validators.validateNIC,
          ),
          _AuthField(
            controller: _homeAddressController,
            label: 'Home Address',
            minLines: 2,
            maxLines: 3,
            validator: (v) => Validators.validateRequired(v, 'Home Address'),
          ),
          _AuthField(
            controller: _emergencyContactController,
            label: 'Emergency Contact',
            keyboardType: TextInputType.phone,
            validator: Validators.validatePhoneNumber,
          ),
        ],
      );
    }

    return Column(
      children: [
        _VehicleTypeField(
          vehicleType: _vehicleType,
          onChanged: (v) => setState(() => _vehicleType = v),
        ),
        _AuthField(
          controller: _vehicleNumberController,
          label: 'Vehicle Number',
          validator: Validators.validateVehicleNumber,
        ),
        _AuthField(
          controller: _drivingLicenseController,
          label: 'Driving License Number',
          validator: (v) =>
              Validators.validateRequired(v, 'Driving License Number'),
        ),
      ],
    );
  }
}

class _AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AuthHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _brandOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.delivery_dining, color: _brandOrange),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: _textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int currentStep;
  final String title;
  final String subtitle;

  const _StepHeader({
    required this.currentStep,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Step ${currentStep + 1} of 3',
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (i) {
              final isActive = i <= currentStep;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: isActive ? _brandOrange : Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.minLines,
    this.maxLines,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            minLines: minLines,
            maxLines: maxLines ?? 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: _authInputDecoration(
              hint: label,
              suffixIcon: suffixIcon,
            ),
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
          const Text(
            'Vehicle Type',
            style: TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
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
            decoration: _authInputDecoration(hint: 'Vehicle Type'),
            items: const [
              DropdownMenuItem(value: 'Bike', child: Text('Bike')),
              DropdownMenuItem(
                value: 'Three Wheeler',
                child: Text('Three Wheeler'),
              ),
              DropdownMenuItem(value: 'Van', child: Text('Van')),
            ],
            onChanged: onChanged,
            validator: (_) {
              if (vehicleType == null) return 'This field is required';
              return null;
            },
          ),
        ],
      ),
    );
  }
}

class _RegisterActions extends StatelessWidget {
  final int currentStep;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  const _RegisterActions({
    required this.currentStep,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: const BoxDecoration(
          color: _appBg,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: onBack == null
                          ? Colors.white30
                          : _textMuted,
                      side: BorderSide(
                        color: onBack == null ? Colors.white12 : _border,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onNext,
                    style: _primaryButtonStyle(),
                    child: Text(currentStep == 2 ? 'Register' : 'Next'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to login'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SurfacePanel({required this.child, required this.padding});

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

ButtonStyle _primaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: _brandOrange,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    minimumSize: const Size.fromHeight(48),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
  );
}

InputDecoration _authInputDecoration({
  required String hint,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    suffixIcon: suffixIcon,
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
