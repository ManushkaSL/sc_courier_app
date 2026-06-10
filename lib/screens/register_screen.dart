import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/premium_button.dart';
import '../services/supabase_service.dart';
import '../utils/validators.dart';
import 'dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const String routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
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
  XFile? _nicFrontImage;
  XFile? _nicBackImage;

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

  String? _getFileName(XFile? file) {
    if (file == null) return null;
    final normalized = file.path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  Future<void> _pickNicPhoto({required bool isFront}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final pickedImage = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
    );

    if (pickedImage == null || !mounted) return;

    setState(() {
      if (isFront) {
        _nicFrontImage = pickedImage;
      } else {
        _nicBackImage = pickedImage;
      }
    });
  }

  bool _validateCurrentStep() {
    final formState = _formKey.currentState;
    if (formState == null) return false;
    if (!formState.validate()) return false;

    if (_currentStep == 1) {
      if (_nicFrontImage == null || _nicBackImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload both NIC front and back photos.'),
          ),
        );
        return false;
      }
    }

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
    setState(() => _isLoading = true);

    try {
      // Sign up with Supabase
      await _supabaseService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Create user profile
      final userId = _supabaseService.currentUser?.id;
      if (userId != null) {
        await _supabaseService.createUserProfile(
          userId: userId,
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          phoneNumber: _phoneNumberController.text.trim(),
          vehicleType: _vehicleType,
          vehicleNumber: _vehicleNumberController.text.trim(),
        );
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        DashboardScreen.routeName,
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        String errorMessage = e.toString();
        
        // Provide user-friendly error messages
        if (errorMessage.contains('rate limit')) {
          errorMessage = 'Too many registration attempts. Please wait a few minutes and try again with a different email.';
        } else if (errorMessage.contains('already registered') || errorMessage.contains('user already exists')) {
          errorMessage = 'This email is already registered. Try logging in or use a different email.';
        } else if (errorMessage.contains('invalid email')) {
          errorMessage = 'Invalid email format. Please check your email address.';
        } else if (errorMessage.contains('password')) {
          errorMessage = 'Password must be at least 6 characters.';
        } else {
          errorMessage = 'Registration failed: $errorMessage';
        }
        
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
                                    Text(
                                      'Upload NIC Photo',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _glassUploadButton(
                                            label: 'Front',
                                            file: _nicFrontImage,
                                            onTap: () =>
                                                _pickNicPhoto(isFront: true),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _glassUploadButton(
                                            label: 'Back',
                                            file: _nicBackImage,
                                            onTap: () =>
                                                _pickNicPhoto(isFront: false),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
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

  Widget _glassUploadButton({
    required String label,
    required XFile? file,
    required VoidCallback onTap,
  }) {
    final picked = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: picked
              ? const Color(0xFFF97316).withOpacity(0.12)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: picked
                ? const Color(0xFFF97316).withOpacity(0.6)
                : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Column(
          children: [
            Icon(
              picked ? Icons.check_circle_outline : Icons.upload_file,
              color: picked ? const Color(0xFFF97316) : Colors.white54,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              picked ? (_getFileName(file) ?? label) : 'Upload $label',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: picked ? const Color(0xFFF97316) : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
