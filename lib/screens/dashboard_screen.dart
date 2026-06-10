import 'dart:ui';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'extend_delivery_screen.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';

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

      // Fetch user profile
      final profile = await _supabaseService.getUserProfile(currentUser.id);
      if (profile != null) {
        riderName = profile['full_name'] ?? 'Rider';
      }

      // Fetch deliveries
      final deliveries = await _supabaseService.getDeliveries();

      // Fetch stats
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

  @override
  Widget build(BuildContext context) {
    final isTracking = _locationService.isTracking;
    final position = _locationService.currentPosition;
    final gpsColor = isTracking ? const Color(0xFF4ADE80) : Colors.white38;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, color: Color(0xFFF97316)),
            tooltip: 'Refresh deliveries',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFFF97316)),
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.pushNamed(context, SettingsScreen.routeName),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFF97316)),
            tooltip: 'Logout',
            onPressed: () async {
              await _supabaseService.signOut();
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  LoginScreen.routeName,
                  (_) => false,
                );
              }
            },
          ),
        ],
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
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: const Color(0xFFF97316),
            backgroundColor: const Color(0xFF2A2A2A),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome glass card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(22),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF97316,
                                ).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delivery_dining,
                                color: Color(0xFFF97316),
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    riderName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Ready for deliveries?',
                                    style: TextStyle(
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF97316,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(
                                    0xFFF97316,
                                  ).withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'Online',
                                style: TextStyle(
                                  color: Color(0xFFF97316),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ─── GPS Tracking Status Card ─────────────────────────────
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, SettingsScreen.routeName),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          decoration: BoxDecoration(
                            color: isTracking
                                ? const Color(
                                    0xFF4ADE80,
                                  ).withValues(alpha: 0.07)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isTracking
                                  ? const Color(
                                      0xFF4ADE80,
                                    ).withValues(alpha: 0.30)
                                  : Colors.white.withValues(alpha: 0.09),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: gpsColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isTracking ? Icons.gps_fixed : Icons.gps_off,
                                  color: gpsColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isTracking
                                          ? 'GPS Tracking Active'
                                          : 'GPS Tracking Off',
                                      style: TextStyle(
                                        color: gpsColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      position != null
                                          ? '${position.latitude.toStringAsFixed(4)}, '
                                                '${position.longitude.toStringAsFixed(4)}'
                                          : isTracking
                                          ? 'Getting location…'
                                          : 'Tap to open settings',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.45,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.check_circle_outline,
                          label: 'Delivered',
                          value: _stats['completed'].toString(),
                          color: const Color(0xFF4ADE80),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.pending_outlined,
                          label: 'Pending',
                          value: _stats['pending'].toString(),
                          color: const Color(0xFFF97316),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.attach_money,
                          label: 'Earnings',
                          value:
                              'Rs. ${_stats['total_earnings']?.toStringAsFixed(2) ?? '0.00'}',
                          color: const Color(0xFF4ADE80),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Active deliveries glass card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_shipping_outlined,
                                  color: Color(0xFFF97316),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Active Deliveries',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_isLoading)
                              const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFF97316),
                                ),
                              )
                            else if (_deliveries.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.inbox_outlined,
                                        color: Colors.white.withOpacity(0.3),
                                        size: 40,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No active deliveries',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.white.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                  child: DataTable(
                                    headingTextStyle: const TextStyle(
                                      color: Color(0xFFF97316),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                    dataTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    columnSpacing: 20,
                                    columns: const [
                                      DataColumn(label: Text('ID')),
                                      DataColumn(label: Text('Location')),
                                      DataColumn(label: Text('Status')),
                                    ],
                                    rows: _deliveries
                                        .map(
                                          (delivery) => DataRow(
                                            cells: [
                                              DataCell(
                                                Text(
                                                  delivery['id']
                                                          ?.toString()
                                                          .substring(0, 8) ??
                                                      'N/A',
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  delivery['delivery_address'] ??
                                                      'Unknown',
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        (delivery['status'] ==
                                                                    'completed'
                                                                ? const Color(
                                                                    0xFF4ADE80,
                                                                  )
                                                                : const Color(
                                                                    0xFFF97316,
                                                                  ))
                                                            .withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    delivery['status'] ??
                                                        'Unknown',
                                                    style: TextStyle(
                                                      color:
                                                          delivery['status'] ==
                                                              'completed'
                                                          ? const Color(
                                                              0xFF4ADE80,
                                                            )
                                                          : const Color(
                                                              0xFFF97316,
                                                            ),
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Extend Delivery Button
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF97316,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(
                              0xFFF97316,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFF97316,
                                    ).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_location_alt_outlined,
                                    color: Color(0xFFF97316),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Add New Delivery',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Extend your delivery list',
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
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.pushNamed(
                                context,
                                ExtendDeliveryScreen.routeName,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Extend Delivery'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
