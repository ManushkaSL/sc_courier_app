import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final _locationService = LocationService();
  GoogleMapController? _mapController;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _locationService.addListener(_onLocationChanged);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationChanged);
    _mapController?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final position = _locationService.currentPosition;
    setState(() {});
    if (position != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    }
  }

  Future<void> _toggleTracking() async {
    if (_locationService.isTracking) {
      await _locationService.stopTracking();
    } else {
      final error = await _locationService.startTracking();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: _locationService.openAppSettings,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = _locationService.isTracking;
    final position = _locationService.currentPosition;
    final riderLatLng = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final statusMsg = _locationService.statusMessage;

    final trackingColor = isTracking ? const Color(0xFF4ADE80) : Colors.white38;
    final trackingLabel = isTracking ? 'Tracking Active' : 'Tracking Inactive';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── GPS Tracking Card ───────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isTracking
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.35)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isTracking
                                ? const Color(
                                    0xFF4ADE80,
                                  ).withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header row
                          Row(
                            children: [
                              // Animated pulse indicator
                              AnimatedBuilder(
                                animation: _pulseCtrl,
                                builder: (context, child) => Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: trackingColor.withValues(
                                      alpha: isTracking
                                          ? 0.1 + 0.1 * _pulseCtrl.value
                                          : 0.08,
                                    ),
                                    border: Border.all(
                                      color: trackingColor.withValues(
                                        alpha: isTracking
                                            ? 0.5 + 0.3 * _pulseCtrl.value
                                            : 0.25,
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    isTracking
                                        ? Icons.gps_fixed
                                        : Icons.gps_off,
                                    color: trackingColor,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'GPS Location Tracking',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      trackingLabel,
                                      style: TextStyle(
                                        color: trackingColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Toggle switch
                              GestureDetector(
                                onTap: _toggleTracking,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: 52,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(15),
                                    color: isTracking
                                        ? const Color(0xFF4ADE80)
                                        : Colors.white.withValues(alpha: 0.15),
                                    border: Border.all(
                                      color: isTracking
                                          ? const Color(0xFF4ADE80)
                                          : Colors.white.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: AnimatedAlign(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOut,
                                    alignment: isTracking
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.all(3),
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Status / coordinates area
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoRow(
                                  icon: Icons.info_outline,
                                  label: 'Status',
                                  value: statusMsg,
                                  valueColor: isTracking
                                      ? const Color(0xFF4ADE80)
                                      : Colors.white54,
                                ),
                                if (position != null) ...[
                                  const SizedBox(height: 10),
                                  _InfoRow(
                                    icon: Icons.my_location,
                                    label: 'Latitude',
                                    value: position.latitude.toStringAsFixed(6),
                                  ),
                                  const SizedBox(height: 10),
                                  _InfoRow(
                                    icon: Icons.my_location,
                                    label: 'Longitude',
                                    value: position.longitude.toStringAsFixed(
                                      6,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _InfoRow(
                                    icon: Icons.speed,
                                    label: 'Speed',
                                    value:
                                        '${(position.speed * 3.6).toStringAsFixed(1)} km/h',
                                  ),
                                  const SizedBox(height: 10),
                                  _InfoRow(
                                    icon:
                                        Icons.precision_manufacturing_outlined,
                                    label: 'Accuracy',
                                    value:
                                        '±${position.accuracy.toStringAsFixed(1)} m',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _RiderLocationMap(
                            riderLatLng: riderLatLng,
                            isTracking: isTracking,
                            onMapCreated: (controller) {
                              _mapController = controller;
                              if (riderLatLng != null) {
                                controller.animateCamera(
                                  CameraUpdate.newLatLngZoom(riderLatLng, 16),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          // Big action button
                          _GpsActionButton(
                            isTracking: isTracking,
                            onTap: _toggleTracking,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                // ─── Device Settings shortcut ────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.09),
                        ),
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            icon: Icons.settings_outlined,
                            label: 'App Location Settings',
                            subtitle: 'Manage location permission',
                            onTap: _locationService.openAppSettings,
                          ),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.07),
                            indent: 58,
                          ),
                          _SettingsTile(
                            icon: Icons.location_on_outlined,
                            label: 'Device Location Settings',
                            subtitle: 'Open device GPS settings',
                            onTap: _locationService.openLocationSettings,
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
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _RiderLocationMap extends StatelessWidget {
  final LatLng? riderLatLng;
  final bool isTracking;
  final ValueChanged<GoogleMapController> onMapCreated;

  const _RiderLocationMap({
    required this.riderLatLng,
    required this.isTracking,
    required this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    final currentLatLng = riderLatLng;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 220,
        child: currentLatLng == null
            ? Container(
                color: Colors.white.withValues(alpha: 0.05),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTracking ? Icons.location_searching : Icons.map,
                      color: const Color(0xFFF97316),
                      size: 34,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isTracking
                          ? 'Waiting for rider location...'
                          : 'Start GPS to show rider location',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: currentLatLng,
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('rider_current_location'),
                    position: currentLatLng,
                    infoWindow: const InfoWindow(title: 'Rider location'),
                  ),
                },
                onMapCreated: onMapCreated,
                myLocationEnabled: isTracking,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
              ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFF97316), size: 16),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _GpsActionButton extends StatefulWidget {
  final bool isTracking;
  final VoidCallback onTap;

  const _GpsActionButton({required this.isTracking, required this.onTap});

  @override
  State<_GpsActionButton> createState() => _GpsActionButtonState();
}

class _GpsActionButtonState extends State<_GpsActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
      lowerBound: 0,
      upperBound: 1,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = widget.isTracking;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isTracking
                  ? [const Color(0xFF16A34A), const Color(0xFF4ADE80)]
                  : [const Color(0xFFFF7A00), const Color(0xFFF97316)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:
                    (isTracking
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFF97316))
                        .withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTracking ? Icons.stop_circle_outlined : Icons.gps_fixed,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                isTracking ? 'Stop Tracking' : 'Start Tracking',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFFF97316), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
