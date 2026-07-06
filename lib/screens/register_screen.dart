import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/supabase_service.dart';
import '../utils/validators.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/premium_button.dart';
import 'dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const String routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isLoading = false;
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

  bool _isFieldInCurrentStep(String label) {
    const step0Labels = {
      'Full Name',
      'Phone Number',
      'Branch',
      'Email',
      'Password',
      'Confirm Password',
    };
    const step1Labels = {'NIC Number', 'Home Address', 'Emergency Contact'};
    const step2Labels = {'Vehicle Number', 'Driving License Number'};

    if (_currentStep == 0) return step0Labels.contains(label);
    if (_currentStep == 1) return step1Labels.contains(label);
    return step2Labels.contains(label);
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
      // Create Firebase auth user
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          )
          .timeout(const Duration(seconds: 30));

      // NIC image upload is temporarily disabled — save profile without images.
      final userId = cred.user?.uid;
      if (userId == null) {
        throw Exception('Could not create Firebase user.');
      }
      createdUser = cred.user;

      final nic = _nicNumberController.text.trim();
      final frontUrl = null;
      final backUrl = null;

      final riderPayload = {
        'NIC': nic,
        'Name': _fullNameController.text.trim(),
        'Phone_Number': _phoneNumberController.text.trim(),
        'Branch': _branchController.text.trim(),
        'Email': _emailController.text.trim(),
        'NIC_Front_Image': frontUrl,
        'NIC_Back_Image': backUrl,
        'Address': _homeAddressController.text.trim(),
        'Emergency_Contact': _emergencyContactController.text.trim(),
        'Vehicle_Type': _vehicleType,
        'Vehicle_No': _vehicleNumberController.text.trim(),
        'Driver_Licence_No': _drivingLicenseController.text.trim(),
        'firebase_uid': userId,
        'created_at': FieldValue.serverTimestamp(),
        'created_at_iso': DateTime.now().toIso8601String(),
      };

      await FirestoreService().saveRider(riderPayload);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        DashboardScreen.routeName,
        (_) => false,
      );
    } catch (e) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (createdUser != null && authUser?.uid == createdUser.uid) {
        try {
          await authUser?.delete();
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
      return 'Registration is taking too long. Please try again or check Firebase rules.';
    }

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'This email is already registered. Try logging in or use a different email.';
        case 'invalid-email':
          return 'Invalid email format. Please check your email address.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'too-many-requests':
          return 'Too many registration attempts. Please wait a few minutes and try again.';
      }
    }

    if (error is FirebaseException) {
      if (error.code == 'permission-denied' || error.code == 'unauthorized') {
        return 'Firebase permission denied. Deploy updated Firestore/Storage rules then try again.';
      }
      return 'Firebase error (${error.code}): ${error.message ?? error.toString()}';
    }

    final rawMessage = error.toString();
    if (rawMessage.contains('permission-denied') ||
        rawMessage.contains('unauthorized') ||
        rawMessage.contains('403')) {
      return 'Firebase permission denied. Deploy updated Firestore/Storage rules then try again.';
    }

    return 'Registration failed: $rawMessage';
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['Basic Info', 'Personal Info', 'Vehicle Info'];
    final stepIcons = [
      Icons.person_outline,
      Icons.badge_outlined,
      Icons.directions_car_outlined,
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 28, width: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'SC Courier Rider App',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A1A), Color(0xFF212121), Color(0xFF1A1A1A)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // Step indicator
                    Row(
                      children: List.generate(3, (i) {
                        final isActive = i == _currentStep;
                        final isDone = i < _currentStep;
                        return Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: 4,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: isDone || isActive
                                        ? const Color(0xFFF97316)
                                        : Colors.white.withOpacity(0.15),
                                  ),
                                ),
                              ),
                              if (i < 2) const SizedBox(width: 4),
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            stepIcons[_currentStep],
                            color: const Color(0xFFF97316),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stepTitles[_currentStep],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Step ${_currentStep + 1} of 3',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Glass form card
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_currentStep == 0) ...[
                                    _glassField(
                                      controller: _fullNameController,
                                      label: 'Full Name',
                                      icon: Icons.person_outline,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('Full Name')
                                          ? Validators.validateName(v)
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _phoneNumberController,
                                      label: 'Phone Number',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('Phone Number')
                                          ? Validators.validatePhoneNumber(v)
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _branchController,
                                      label: 'Branch',
                                      icon: Icons.store_outlined,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('Branch')
                                          ? Validators.validateRequired(
                                              v,
                                              'Branch',
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _emailController,
                                      label: 'Email',
                                      icon: Icons.email_outlined,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('Email')
                                          ? Validators.validateEmail(v)
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _passwordController,
                                      label: 'Password',
                                      icon: Icons.lock_outline,
                                      obscureText: true,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('Password')
                                          ? Validators.validatePassword(v)
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _confirmPasswordController,
                                      label: 'Confirm Password',
                                      icon: Icons.lock_outline,
                                      obscureText: true,
                                      validator: (v) {
                                        if (!_isFieldInCurrentStep(
                                          'Confirm Password',
                                        ))
                                          return null;
                                        return Validators.validatePasswordMatch(
                                          v,
                                          _passwordController.text,
                                        );
                                      },
                                    ),
                                  ],
                                  if (_currentStep == 1) ...[
                                    _glassField(
                                      controller: _nicNumberController,
                                      label: 'NIC Number',
                                      icon: Icons.credit_card_outlined,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('NIC Number')
                                          ? Validators.validateNIC(v)
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                    _glassField(
                                      controller: _homeAddressController,
                                      label: 'Home Address',
                                      icon: Icons.home_outlined,
                                      minLines: 2,
                                      maxLines: 3,
                                      validator: (v) =>
                                          _isFieldInCurrentStep('Home Address')
                                          ? Validators.validateRequired(
                                              v,
                                              'Home Address',
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _emergencyContactController,
                                      label: 'Emergency Contact',
                                      icon: Icons.emergency_outlined,
                                      keyboardType: TextInputType.phone,
                                      validator: (v) =>
                                          _isFieldInCurrentStep(
                                            'Emergency Contact',
                                          )
                                          ? Validators.validatePhoneNumber(v)
                                          : null,
                                    ),
                                  ],
                                  if (_currentStep == 2) ...[
                                    DropdownButtonFormField<String>(
                                      initialValue: _vehicleType,
                                      dropdownColor: const Color(0xFF232323),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Vehicle Type',
                                        prefixIcon: const Icon(
                                          Icons.directions_car_outlined,
                                          color: Color(0xFFF97316),
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(
                                          0.07,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.15,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFF97316),
                                            width: 1.8,
                                          ),
                                        ),
                                        labelStyle: const TextStyle(
                                          color: Color(0xFFBBBBBB),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 16,
                                            ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'Bike',
                                          child: Text('Bike'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Three Wheeler',
                                          child: Text('Three Wheeler'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Van',
                                          child: Text('Van'),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _vehicleType = v),
                                      validator: (_) {
                                        if (_currentStep != 2) return null;
                                        if (_vehicleType == null)
                                          return 'This field is required';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _vehicleNumberController,
                                      label: 'Vehicle Number',
                                      icon: Icons.pin_outlined,
                                      validator: (v) =>
                                          _isFieldInCurrentStep(
                                            'Vehicle Number',
                                          )
                                          ? Validators.validateVehicleNumber(v)
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _glassField(
                                      controller: _drivingLicenseController,
                                      label: 'Driving License Number',
                                      icon: Icons.article_outlined,
                                      validator: (v) =>
                                          _isFieldInCurrentStep(
                                            'Driving License Number',
                                          )
                                          ? Validators.validateRequired(
                                              v,
                                              'Driving License Number',
                                            )
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GlassOutlineButton(
                            label: 'Back',
                            disabled: _currentStep == 0,
                            onPressed: _currentStep == 0 ? null : _backStep,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PremiumButton(
                            label: _currentStep == 2 ? 'Register' : 'Next',
                            onPressed: _currentStep == 2
                                ? _handleRegister
                                : _nextStep,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to login'),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    int? minLines,
    int? maxLines,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines ?? 1,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFFF97316), size: 20),
      ),
      validator: validator,
    );
  }
}
