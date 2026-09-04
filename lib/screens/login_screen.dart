import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/validators.dart';
import '../widgets/loading_overlay.dart';
import 'dashboard_screen.dart';
import 'register_screen.dart';

const _brandOrange = Color(0xFFF97316);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _surfaceSoft = Color(0xFF2A2A2A);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const String routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabaseService = SupabaseService();
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _showResendConfirmation = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    setState(() {
      _errorMessage = null;
      _showResendConfirmation = false;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();

    try {
      await _supabaseService.signIn(
        email: email,
        password: _passwordController.text,
      );
    } catch (e) {
      final resolved = await _resolveLoginError(e, email);

      if (!mounted) return;
      setState(() {
        _errorMessage = resolved.message;
        _showResendConfirmation = resolved.offerResend;
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      DashboardScreen.routeName,
      (_) => false,
    );
  }

  /// Supabase returns a generic `invalid_credentials` error both for a wrong
  /// password and (on projects with email confirmation on) for an account that
  /// was created but never confirmed, so check the rider record before deciding
  /// which message to show.
  Future<_LoginError> _resolveLoginError(Object error, String email) async {
    if (error is AuthException) {
      final code = error.code ?? '';
      final message = error.message.toLowerCase();

      if (code == 'email_not_confirmed' ||
          message.contains('email not confirmed')) {
        return const _LoginError(
          'Your email address is not confirmed yet. Open the confirmation link '
          'we emailed you, then log in again.',
          offerResend: true,
        );
      }

      if (code == 'over_request_rate_limit' ||
          code == 'over_email_send_rate_limit' ||
          message.contains('rate limit')) {
        return const _LoginError(
          'Too many login attempts. Please wait a few minutes and try again.',
        );
      }

      if (code == 'invalid_credentials' ||
          message.contains('invalid login credentials') ||
          message.contains('invalid credentials')) {
        final hasRiderRecord = await _supabaseService.riderExistsForEmail(
          email,
        );
        if (hasRiderRecord) {
          return const _LoginError(
            'This account exists but is not confirmed yet, so login is blocked. '
            'Confirm your email address, then log in again.',
            offerResend: true,
          );
        }
        return const _LoginError(
          'Invalid email or password. Please try again.',
        );
      }

      return _LoginError(error.message);
    }

    final raw = error.toString().replaceAll('Exception: ', '');
    if (raw.contains('rate limit')) {
      return const _LoginError(
        'Too many login attempts. Please wait a few minutes and try again.',
      );
    }
    return _LoginError(raw);
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email address first.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabaseService.sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is AuthException
          ? e.message
          : e.toString().replaceAll('Exception: ', '');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not send the reset email: $message';
      });
    }
  }

  Future<void> _handleResendConfirmation() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email address first.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabaseService.resendConfirmationEmail(email);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _showResendConfirmation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirmation email sent to $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is AuthException
          ? e.message
          : e.toString().replaceAll('Exception: ', '');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not resend the confirmation email: $message';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Lottie.asset(
                'assets/Courier.json',
                height: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              const _AuthHeader(
                title: 'Welcome Back',
                subtitle: 'Sign in to manage your deliveries.',
              ),
              const SizedBox(height: 22),
              _SurfacePanel(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        _ErrorBanner(message: _errorMessage!),
                        const SizedBox(height: 8),
                      ],
                      if (_showResendConfirmation) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : _handleResendConfirmation,
                            child: const Text('Resend confirmation email'),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      _AuthField(
                        controller: _emailController,
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: Validators.validateEmail,
                      ),
                      const SizedBox(height: 12),
                      _AuthField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: _obscurePassword,
                        validator: Validators.validatePassword,
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: _textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _handleForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: _primaryButtonStyle(),
                          child: const Text('Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: _textMuted, fontSize: 14),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, RegisterScreen.routeName);
                    },
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AuthHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 13),
        ),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: _authInputDecoration(hint: label, suffixIcon: suffixIcon),
          validator: validator,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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

class _LoginError {
  final String message;
  final bool offerResend;

  const _LoginError(this.message, {this.offerResend = false});
}
