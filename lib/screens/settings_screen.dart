import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';

const _brandOrange = Color(0xFFF97316);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _locationService = LocationService();
  final _supabaseService = SupabaseService();
  bool _profileChanged = false;
  bool _handledRouteArguments = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledRouteArguments) return;
    _handledRouteArguments = true;

    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! Map || arguments['profileSaved'] != true) return;

    _profileChanged = true;
    final photoUploadSkipped = arguments['photoUploadSkipped'] == true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showProfileSavedMessage(photoUploadSkipped: photoUploadSkipped);
    });
  }

  Future<void> _logout() async {
    if (_locationService.isTracking) {
      await _locationService.stopTracking();
    }
    await _supabaseService.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      LoginScreen.routeName,
      (_) => false,
    );
  }

  Future<void> _openProfileSettings() async {
    final updatedProfile = await Navigator.pushNamed(
      context,
      ProfileSettingsScreen.routeName,
    );
    if (!mounted || updatedProfile == null) return;

    final photoUploadSkipped =
        updatedProfile is Map && updatedProfile['photoUploadSkipped'] == true;
    setState(() => _profileChanged = true);
    _showProfileSavedMessage(photoUploadSkipped: photoUploadSkipped);
  }

  void _showProfileSavedMessage({required bool photoUploadSkipped}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          photoUploadSkipped
              ? 'Profile saved. Photo upload skipped because storage is not set up.'
              : 'Profile settings saved successfully.',
        ),
      ),
    );
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
          onPressed: () => Navigator.pop(context, _profileChanged),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const _SettingsSectionTitle('Account'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.person_outline,
                  label: 'Profile',
                  subtitle: 'Name, phone, photo, and vehicle details',
                  onTap: _openProfileSettings,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _SettingsSectionTitle('Permissions'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.tune_outlined,
                  label: 'App Location Permission',
                  subtitle: 'Manage this app permission',
                  onTap: _locationService.openAppSettings,
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.location_on_outlined,
                  label: 'Device GPS',
                  subtitle: 'Open device location settings',
                  onTap: _locationService.openLocationSettings,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _SettingsSectionTitle('Account Access'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.logout,
                  label: 'Logout',
                  subtitle: 'Sign out from this rider account',
                  iconColor: Colors.redAccent,
                  onTap: _logout,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  final String label;

  const _SettingsSectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: _textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: Colors.white10, indent: 58);
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.iconColor = _brandOrange,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
            ],
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
