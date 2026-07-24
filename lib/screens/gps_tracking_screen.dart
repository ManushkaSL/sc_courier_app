import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';

const _brandOrange = Color(0xFFF97316);
const _successGreen = Color(0xFF4ADE80);
const _warning = Color(0xFFFFB020);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _surfaceSoft = Color(0xFF2A2A2A);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);

class GpsTrackingScreen extends StatefulWidget {
  const GpsTrackingScreen({super.key});

  static const String routeName = '/gps_tracking';

  @override
  State<GpsTrackingScreen> createState() => _GpsTrackingScreenState();
}

class _GpsTrackingScreenState extends State<GpsTrackingScreen> {
  final _locationService = LocationService();
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _locationService.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationChanged);
    _mapController?.dispose();
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
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final isTracking = _locationService.isTracking;
    final position = _locationService.currentPosition;
    final riderLatLng = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final color = isTracking ? _successGreen : _warning;

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
          'GPS Tracking',
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
            _StatusPanel(
              isTracking: isTracking,
              statusMessage: _locationService.statusMessage,
              color: color,
              onToggle: _toggleTracking,
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 18),
            _LocationDetails(position: position),
            const SizedBox(height: 18),
            _SettingsActions(locationService: _locationService),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final bool isTracking;
  final String statusMessage;
  final Color color;
  final VoidCallback onToggle;

  const _StatusPanel({
    required this.isTracking,
    required this.statusMessage,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      borderColor: color.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isTracking ? Icons.gps_fixed : Icons.gps_off,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTracking ? 'GPS tracking active' : 'GPS tracking is off',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onToggle,
              icon: Icon(
                isTracking ? Icons.stop_circle_outlined : Icons.gps_fixed,
              ),
              label: Text(isTracking ? 'Stop Tracking' : 'Start Tracking'),
              style: FilledButton.styleFrom(
                backgroundColor: isTracking ? _successGreen : _brandOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final supportsEmbeddedMap =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final placeholderText = !supportsEmbeddedMap && currentLatLng != null
        ? '${currentLatLng.latitude.toStringAsFixed(6)}, '
              '${currentLatLng.longitude.toStringAsFixed(6)}'
        : isTracking
        ? 'Waiting for rider location'
        : 'Start GPS to show rider location';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 240,
        child: currentLatLng == null || !supportsEmbeddedMap
            ? Container(
                color: _surfaceSoft,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTracking
                          ? Icons.location_searching
                          : Icons.map_outlined,
                      color: isTracking ? _successGreen : _textMuted,
                      size: 34,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      placeholderText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textMuted,
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

class _LocationDetails extends StatelessWidget {
  final Position? position;

  const _LocationDetails({required this.position});

  @override
  Widget build(BuildContext context) {
    final currentPosition = position;

    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Live Details'),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Latitude',
            value: currentPosition == null
                ? 'Not available'
                : currentPosition.latitude.toStringAsFixed(6),
          ),
          const _DetailDivider(),
          _DetailRow(
            label: 'Longitude',
            value: currentPosition == null
                ? 'Not available'
                : currentPosition.longitude.toStringAsFixed(6),
          ),
          const _DetailDivider(),
          _DetailRow(
            label: 'Speed',
            value: currentPosition == null
                ? 'Not available'
                : '${(currentPosition.speed * 3.6).toStringAsFixed(1)} km/h',
          ),
          const _DetailDivider(),
          _DetailRow(
            label: 'Accuracy',
            value: currentPosition == null
                ? 'Not available'
                : '+/- ${currentPosition.accuracy.toStringAsFixed(1)} m',
          ),
        ],
      ),
    );
  }
}

class _SettingsActions extends StatelessWidget {
  final LocationService locationService;

  const _SettingsActions({required this.locationService});

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ActionTile(
            icon: Icons.tune_outlined,
            label: 'App Location Permission',
            subtitle: 'Manage this app permission',
            onTap: locationService.openAppSettings,
          ),
          const _DetailDivider(indent: 58),
          _ActionTile(
            icon: Icons.location_on_outlined,
            label: 'Device GPS',
            subtitle: 'Open device location settings',
            onTap: locationService.openLocationSettings,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
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
                  color: _brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _brandOrange, size: 20),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _DetailDivider extends StatelessWidget {
  final double indent;

  const _DetailDivider({this.indent = 0});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 18, indent: indent, color: Colors.white10);
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
