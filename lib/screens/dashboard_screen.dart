import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'extend_delivery_screen.dart';
import 'gps_tracking_screen.dart';
import 'delivery_details_screen.dart';
import '../services/location_service.dart';
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
  late Map<String, dynamic> _stats = {'completed': 0, 'pending': 0};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _locationService.addListener(_onLocationChanged);
    _loadData();
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final currentUser = _supabaseService.currentUser;
      if (currentUser == null) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          LoginScreen.routeName,
          (_) => false,
        );
        return;
      }

      final profile = await RiderService().getRiderByUid(currentUser.id);
      riderName = _profileValue(profile, ['full_name', 'Name'], 'Rider');

      final deliveries = await _supabaseService.getDeliveries();
      final stats = await _supabaseService.getRiderStats(currentUser.id);

      if (mounted) {
        setState(() {
          _deliveries = deliveries;
          _stats = stats;
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
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            color: Colors.white70,
            tooltip: 'Refresh deliveries',
            onPressed: _loadData,
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
                _RiderHeader(riderName: riderName),
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
                  actionLabel: 'Add',
                  onAction: _openAddDelivery,
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

class _RiderHeader extends StatelessWidget {
  final String riderName;

  const _RiderHeader({required this.riderName});

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Row(
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
                const Text(
                  'Ready for deliveries',
                  style: TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const _StatusPill(label: 'Online', color: _successGreen),
        ],
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
  final Map<String, dynamic> stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_outline,
            label: 'Delivered',
            value: stats['completed'].toString(),
            color: _successGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.pending_outlined,
            label: 'Pending',
            value: stats['pending'].toString(),
            color: const Color(0xFFFFB020),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.payments_outlined,
            label: 'Earnings',
            value:
                'Rs. ${stats['total_earnings']?.toStringAsFixed(2) ?? '0.00'}',
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
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onAction,
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
        if (actionLabel != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel!),
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
    final text = status?.toString() ?? 'Unknown';
    final isCompleted = text == 'completed';
    final color = isCompleted ? _successGreen : const Color(0xFFFFB020);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _formatStatus(text),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
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

String _formatStatus(String status) {
  final text = status.replaceAll('_', ' ').trim();
  if (text.isEmpty) return 'Unknown';
  return text[0].toUpperCase() + text.substring(1);
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
