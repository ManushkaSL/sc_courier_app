import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'extend_delivery_screen.dart';
import 'gps_tracking_screen.dart';
import 'delivery_details_screen.dart';
import 'notifications_screen.dart';
import '../models/delivery_status.dart';
import '../models/rider_availability.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';
import '../services/supabase_service.dart';
import '../services/rider_service.dart';

const _brandOrange = Color(0xFFF97316);
const _successGreen = Color(0xFF4ADE80);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  static const String routeName = '/dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _locationService = LocationService();
  final _supabaseService = SupabaseService();
  late String riderName = '';
  late List<Map<String, dynamic>> _deliveries = [];
  DeliveryStats _stats = const DeliveryStats();
  bool _isLoading = true;
  bool _isRefreshingDeliveries = false;
  bool _isRedirectingToLogin = false;
  RiderAvailability _availability = RiderAvailability.offline;
  bool _isSavingAvailability = false;
  final _pushService = PushNotificationService();
  StreamSubscription<String>? _tokenRefreshSubscription;
  int _unreadNotifications = 0;
  Future<void> Function()? _unsubscribeDeliveries;
  Future<void> Function()? _unsubscribeNotifications;
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _locationService.addListener(_onLocationChanged);
    _loadData();
    _registerForPush();
    _subscribeToRealtime();
  }

  /// Live updates for work the admin assigns while the rider is looking at the
  /// dashboard. The refresh button stays as the manual fallback.
  void _subscribeToRealtime() {
    _unsubscribeDeliveries = _supabaseService.subscribeToDeliveryChanges(
      _onRemoteChange,
    );
  }

  /// A single assignment can touch trip and several delivery rows, so coalesce
  /// the burst into one refetch instead of hammering the API per row.
  void _onRemoteChange() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _refreshDeliveries(silent: true);
    });
  }

  /// Registers this phone so the Edge Function can reach it, and re-registers
  /// whenever FCM rotates the token.
  Future<void> _registerForPush() async {
    try {
      final token = await _pushService.getFCMToken();
      if (token != null) await _supabaseService.saveDeviceToken(token);

      _tokenRefreshSubscription = _pushService.onTokenRefresh((newToken) {
        _supabaseService.saveDeviceToken(newToken);
      });

      final currentUser = await _supabaseService.currentUserOrRestored();
      if (currentUser != null && mounted) {
        _unsubscribeNotifications = _supabaseService.subscribeToNotifications(
          currentUser.id,
          _loadUnreadCount,
        );
      }
    } catch (e) {
      // No push is bad, but it must not take the dashboard down with it.
      debugPrint('Could not register for push notifications: $e');
    }

    // A notification that cold-started the app is handled here rather than in
    // MyApp, so it does not race the splash screen's own navigation.
    final launchPayload = _pushService.takeLaunchPayload();
    if (launchPayload != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openFromNotification(launchPayload);
      });
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _supabaseService.unreadNotificationCount();
      if (!mounted) return;
      setState(() => _unreadNotifications = count);
    } catch (e) {
      debugPrint('Could not load unread notifications: $e');
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.pushNamed(context, NotificationsScreen.routeName);
    if (!mounted) return;
    // The inbox marks things read, so the badge is stale on the way back.
    await _loadUnreadCount();
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationChanged);
    _tokenRefreshSubscription?.cancel();
    _realtimeDebounce?.cancel();
    _unsubscribeDeliveries?.call();
    _unsubscribeNotifications?.call();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final currentUser = await _supabaseService.currentUserOrRestored();
      if (!mounted) return;

      if (currentUser == null) {
        _redirectToLogin();
        return;
      }

      final profile = await RiderService().getRiderByUid(currentUser.id);
      riderName = _profileValue(profile, ['full_name', 'Name'], 'Rider');
      _availability = _supabaseService.availabilityFromProfile(profile);

      final deliveries = await _supabaseService.getAssignedDeliveries();
      unawaited(_loadUnreadCount());

      if (mounted) {
        setState(() {
          _deliveries = deliveries;
          _stats = DeliveryStats.fromDeliveries(deliveries);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  /// [silent] skips the spinner on the refresh button: a realtime update
  /// should not look like the rider pressed something.
  Future<void> _refreshDeliveries({bool silent = false}) async {
    if (_isRefreshingDeliveries) return;
    if (!silent) setState(() => _isRefreshingDeliveries = true);

    try {
      final currentUser = await _supabaseService.currentUserOrRestored();
      if (!mounted) return;

      if (currentUser == null) {
        _redirectToLogin();
        return;
      }

      final deliveries = await _supabaseService.getAssignedDeliveries();
      unawaited(_loadUnreadCount());
      if (!mounted) return;

      setState(() {
        _deliveries = deliveries;
        _stats = DeliveryStats.fromDeliveries(deliveries);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh deliveries: $e')),
      );
    } finally {
      if (mounted && !silent) {
        setState(() => _isRefreshingDeliveries = false);
      }
    }
  }

  Future<void> _pickAvailability() async {
    if (_isSavingAvailability) return;

    final selected = await showModalBottomSheet<RiderAvailability>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AvailabilitySheet(current: _availability),
    );
    if (!mounted || selected == null || selected == _availability) return;

    final messenger = ScaffoldMessenger.of(context);
    final previous = _availability;

    // Optimistic: the pill flips right away and reverts if the write fails.
    setState(() {
      _availability = selected;
      _isSavingAvailability = true;
    });

    try {
      final currentUser = await _supabaseService.currentUserOrRestored();
      if (!mounted) return;
      if (currentUser == null) {
        _redirectToLogin();
        return;
      }

      await _supabaseService.updateRiderAvailability(
        riderId: currentUser.id,
        availability: selected,
      );
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text('Availability set to ${selected.label}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _availability = previous);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save availability: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingAvailability = false);
    }
  }

  void _redirectToLogin() {
    if (_isRedirectingToLogin) return;
    _isRedirectingToLogin = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        LoginScreen.routeName,
        (_) => false,
      );
    });
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  String _profileValue(
    Map<String, dynamic>? profile,
    List<String> keys,
    String fallback,
  ) {
    if (profile == null) return fallback;
    for (final key in keys) {
      final value = profile[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  Future<void> _openSettings() async {
    final shouldReload = await Navigator.pushNamed(
      context,
      SettingsScreen.routeName,
    );
    if (!mounted) return;
    if (shouldReload == true) {
      await _loadData();
    }
  }

  void _openAddDelivery() {
    Navigator.pushNamed(context, ExtendDeliveryScreen.routeName);
  }

  void _openGpsTracking() {
    Navigator.pushNamed(context, GpsTrackingScreen.routeName);
  }

  Future<void> _openDeliveryDetails(Map<String, dynamic> delivery) async {
    await Navigator.pushNamed(
      context,
      DeliveryDetailsScreen.routeName,
      arguments: delivery,
    );
    if (mounted) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = _locationService.isTracking;
    final position = _locationService.currentPosition;

    return Scaffold(
      backgroundColor: _appBg,
      appBar: AppBar(
        backgroundColor: _appBg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
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
        actions: [
          _NotificationBell(
            unreadCount: _unreadNotifications,
            onTap: _openNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            color: Colors.white70,
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: _brandOrange,
          backgroundColor: _surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RiderHeader(
                  riderName: riderName,
                  availability: _availability,
                  isSaving: _isSavingAvailability,
                  onTap: _pickAvailability,
                ),
                const SizedBox(height: 14),
                _GpsStatusTile(
                  isTracking: isTracking,
                  latitude: position?.latitude,
                  longitude: position?.longitude,
                  onTap: _openGpsTracking,
                ),
                const SizedBox(height: 18),
                _StatsRow(stats: _stats),
                const SizedBox(height: 22),
                _SectionHeader(
                  icon: Icons.local_shipping_outlined,
                  label: 'Active Deliveries',
                  isRefreshing: _isRefreshingDeliveries,
                  onRefresh: () => _refreshDeliveries(),
                ),
                const SizedBox(height: 10),
                _ActiveDeliveriesPanel(
                  isLoading: _isLoading,
                  deliveries: _deliveries,
                  onDeliveryTap: _openDeliveryDetails,
                ),
                const SizedBox(height: 18),
                _AddDeliveryPanel(onTap: _openAddDelivery),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _NotificationBell({required this.unreadCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          color: Colors.white70,
          tooltip: 'Notifications',
          onPressed: onTap,
        ),
        if (unreadCount > 0)
          Positioned(
            top: 8,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: _brandOrange,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _appBg, width: 1.5),
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RiderHeader extends StatelessWidget {
  final String riderName;
  final RiderAvailability availability;
  final bool isSaving;
  final VoidCallback onTap;

  const _RiderHeader({
    required this.riderName,
    required this.availability,
    required this.isSaving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: isSaving ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3A2A20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delivery_dining,
                        color: _brandOrange,
                        size: 26,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: availability.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: _surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riderName.isEmpty ? 'Rider' : riderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      availability.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isSaving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brandOrange,
                  ),
                )
              else
                _StatusPill(
                  label: availability.label,
                  color: availability.color,
                ),
              Icon(
                Icons.expand_more,
                size: 20,
                color: _textMuted.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet the rider uses to set their own work state.
class _AvailabilitySheet extends StatelessWidget {
  final RiderAvailability current;

  const _AvailabilitySheet({required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Set your availability',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'New deliveries are only assigned to riders who are available.',
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            for (final option in RiderAvailability.values) ...[
              _AvailabilityOptionTile(
                option: option,
                selected: option == current,
                onTap: () => Navigator.of(context).pop(option),
              ),
              if (option != RiderAvailability.values.last)
                const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvailabilityOptionTile extends StatelessWidget {
  final RiderAvailability option;
  final bool selected;
  final VoidCallback onTap;

  const _AvailabilityOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? option.color.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? option.color : _border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: option.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(option.icon, color: option.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? option.color
                    : _textMuted.withValues(alpha: 0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GpsStatusTile extends StatelessWidget {
  final bool isTracking;
  final double? latitude;
  final double? longitude;
  final VoidCallback onTap;

  const _GpsStatusTile({
    required this.isTracking,
    required this.latitude,
    required this.longitude,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isTracking ? _successGreen : const Color(0xFFFFB020);
    final hasLocation = latitude != null && longitude != null;

    return Material(
      color: isTracking
          ? _successGreen.withValues(alpha: 0.08)
          : const Color(0xFFFFB020).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(isTracking ? Icons.gps_fixed : Icons.gps_off, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTracking
                          ? 'GPS tracking active'
                          : 'GPS tracking is off',
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasLocation
                          ? '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}'
                          : isTracking
                          ? 'Waiting for current location'
                          : 'Open settings to start rider location sharing',
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final DeliveryStats stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    // The three tiles partition the rider's deliveries: nothing is counted
    // twice, so they add up to the work list below.
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.inventory_2_outlined,
            label: 'To pick up',
            value: stats.toPickUp.toString(),
            color: DeliveryStage.assigned.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.local_shipping_outlined,
            label: 'On the way',
            value: stats.onTheWay.toString(),
            color: DeliveryStage.inTransit.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_outline,
            label: 'Delivered',
            value: stats.delivered.toString(),
            color: _successGreen,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  const _SectionHeader({
    required this.icon,
    required this.label,
    this.onRefresh,
    this.isRefreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _brandOrange, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (onRefresh != null)
          IconButton(
            onPressed: isRefreshing ? null : onRefresh,
            tooltip: 'Refresh deliveries',
            visualDensity: VisualDensity.compact,
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _brandOrange,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: _brandOrange,
                  ),
          ),
      ],
    );
  }
}

class _ActiveDeliveriesPanel extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> deliveries;
  final ValueChanged<Map<String, dynamic>> onDeliveryTap;

  const _ActiveDeliveriesPanel({
    required this.isLoading,
    required this.deliveries,
    required this.onDeliveryTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isLoading
            ? const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(color: _brandOrange),
                ),
              )
            : deliveries.isEmpty
            ? const _EmptyDeliveries()
            : _DeliveriesList(
                deliveries: deliveries,
                onDeliveryTap: onDeliveryTap,
              ),
      ),
    );
  }
}

class _EmptyDeliveries extends StatelessWidget {
  const _EmptyDeliveries();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 126,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, color: Colors.white38, size: 34),
            SizedBox(height: 8),
            Text(
              'No active deliveries',
              style: TextStyle(
                color: _textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveriesList extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  final ValueChanged<Map<String, dynamic>> onDeliveryTap;

  const _DeliveriesList({
    required this.deliveries,
    required this.onDeliveryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < deliveries.length; index++) ...[
          _DeliveryListRow(
            delivery: deliveries[index],
            onTap: () => onDeliveryTap(deliveries[index]),
          ),
          if (index != deliveries.length - 1)
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 18),
        ],
      ],
    );
  }
}

class _DeliveryListRow extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final VoidCallback onTap;

  const _DeliveryListRow({required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final code =
        _textValue(delivery, const ['tracking_code', 'parcel_id', 'id']) ??
        'N/A';
    final pickup = _textValue(delivery, const [
      'pickup_address',
      'pickLocation',
      'pick_location',
    ]);
    final dropoff = _textValue(delivery, const [
      'delivery_address',
      'dropLocation',
      'drop_location',
    ]);
    final recipient = _textValue(delivery, const [
      'recipient_name',
      'receiver_name',
      'customer_name',
    ]);
    final price = _priceValue(delivery);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: _brandOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _shortCode(code),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _DeliveryStatus(status: delivery['status']),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CompactDeliveryLine(
                      icon: Icons.inventory_2_outlined,
                      value: pickup ?? 'Pickup not set',
                    ),
                    const SizedBox(height: 5),
                    _CompactDeliveryLine(
                      icon: Icons.location_on_outlined,
                      value: dropoff ?? 'Dropoff not set',
                    ),
                    if (recipient != null || price != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        [?recipient, ?price].join(' | '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.chevron_right, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactDeliveryLine extends StatelessWidget {
  final IconData icon;
  final String value;

  const _CompactDeliveryLine({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _textMuted, size: 15),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _DeliveryStatus extends StatelessWidget {
  final dynamic status;

  const _DeliveryStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final stage = DeliveryStage.fromStatus(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: stage.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: stage.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stage.icon, size: 12, color: stage.color),
          const SizedBox(width: 5),
          Text(
            DeliveryStage.labelFor(status),
            style: TextStyle(
              color: stage.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String? _textValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String _shortCode(String code) {
  if (code.length <= 12) return code;
  return code.substring(0, 12);
}

String? _priceValue(Map<String, dynamic> delivery) {
  final value = _textValue(delivery, const ['price', 'amount', 'delivery_fee']);
  if (value == null) return null;
  final number = num.tryParse(value);
  if (number == null) return value;
  return 'LKR ${number.toStringAsFixed(2)}';
}

class _AddDeliveryPanel extends StatelessWidget {
  final VoidCallback onTap;

  const _AddDeliveryPanel({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      borderColor: _brandOrange.withValues(alpha: 0.22),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _brandOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_location_alt_outlined,
              color: _brandOrange,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Delivery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Create a new delivery request',
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;

  const _SurfacePanel({
    required this.child,
    required this.padding,
    this.borderColor = _border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      padding: padding,
      child: child,
    );
  }
}
