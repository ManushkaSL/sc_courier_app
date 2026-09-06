import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../services/supabase_service.dart';

const _brandOrange = Color(0xFFF97316);
const _successGreen = Color(0xFF4ADE80);
const _warning = Color(0xFFFFB020);
const _pickupBlue = Color(0xFF38BDF8);
const _dropoffPurple = Color(0xFFA78BFA);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
const _surfaceSoft = Color(0xFF2A2A2A);
const _border = Color(0xFF343434);
const _textMuted = Color(0xFFB8B8B8);
const _defaultCenter = LatLng(7.2906, 80.6337);

class GpsTrackingScreen extends StatefulWidget {
  const GpsTrackingScreen({super.key});

  static const String routeName = '/gps_tracking';

  @override
  State<GpsTrackingScreen> createState() => _GpsTrackingScreenState();
}

class _GpsTrackingScreenState extends State<GpsTrackingScreen> {
  final _locationService = LocationService();
  final _supabaseService = SupabaseService();
  final _mapController = MapController();

  List<Map<String, dynamic>> _deliveries = [];
  bool _isDeliveriesLoading = true;
  bool _isTrackingStarting = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _locationService.addListener(_onLocationChanged);
    _loadDeliveries();
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationChanged);
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadDeliveries() async {
    try {
      final deliveries = await _supabaseService.getAssignedDeliveries();
      if (!mounted) return;
      setState(() {
        _deliveries = deliveries.where(_isLiveDelivery).toList();
        _isDeliveriesLoading = false;
      });
      _moveMapToBestCenter();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeliveriesLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load delivery locations: $error')),
      );
    }
  }

  bool _isLiveDelivery(Map<String, dynamic> delivery) {
    const liveStatuses = {
      'pending',
      'accepted',
      'picked_up',
      'in_transit',
      'out_for_delivery',
    };
    return liveStatuses.contains(delivery['status']?.toString());
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {});
    _moveMapToBestCenter();
  }

  void _moveMapToBestCenter() {
    if (!_mapReady) return;
    final center = _riderPoint ?? _deliveryMarkers.firstOrNull?.point;
    if (center != null) {
      _mapController.move(center, 15);
    }
  }

  LatLng? get _riderPoint {
    final position = _locationService.currentPosition;
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  List<_DeliveryMarker> get _deliveryMarkers {
    final markers = <_DeliveryMarker>[];
    for (final delivery in _deliveries) {
      final pickup = _coordinateFromDelivery(
        delivery,
        latKeys: const [
          'pickup_latitude',
          'pickup_lat',
          'pickup_location_latitude',
        ],
        lngKeys: const [
          'pickup_longitude',
          'pickup_lng',
          'pickup_location_longitude',
        ],
        jsonKeys: const ['pickup_location', 'pickup_coordinates'],
      );
      if (pickup != null) {
        markers.add(
          _DeliveryMarker(
            point: pickup,
            label: 'Pickup',
            address: _textValue(delivery, ['pickup_address']),
            color: _pickupBlue,
            icon: Icons.inventory_2_outlined,
          ),
        );
      }

      final dropoff = _coordinateFromDelivery(
        delivery,
        latKeys: const [
          'delivery_latitude',
          'delivery_lat',
          'dropoff_latitude',
          'dropoff_lat',
        ],
        lngKeys: const [
          'delivery_longitude',
          'delivery_lng',
          'dropoff_longitude',
          'dropoff_lng',
        ],
        jsonKeys: const [
          'delivery_location',
          'delivery_coordinates',
          'dropoff_location',
        ],
      );
      if (dropoff != null) {
        markers.add(
          _DeliveryMarker(
            point: dropoff,
            label: 'Dropoff',
            address: _textValue(delivery, ['delivery_address']),
            color: _dropoffPurple,
            icon: Icons.location_on_outlined,
          ),
        );
      }
    }
    return markers;
  }

  LatLng? _coordinateFromDelivery(
    Map<String, dynamic> delivery, {
    required List<String> latKeys,
    required List<String> lngKeys,
    required List<String> jsonKeys,
  }) {
    final directLat = _numberFromKeys(delivery, latKeys);
    final directLng = _numberFromKeys(delivery, lngKeys);
    if (directLat != null && directLng != null) return LatLng(directLat, directLng);

    for (final key in jsonKeys) {
      final value = delivery[key];
      if (value is! Map) continue;
      final lat = _numberFromKeys(Map<String, dynamic>.from(value), [
        'latitude',
        'lat',
      ]);
      final lng = _numberFromKeys(Map<String, dynamic>.from(value), [
        'longitude',
        'lng',
      ]);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null;
  }

  double? _numberFromKeys(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.trim());
    }
    return null;
  }

  String _textValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'Address not available';
  }

  Future<void> _toggleTracking() async {
    if (_isTrackingStarting) return;

    if (_locationService.isTracking) {
      await _locationService.stopTracking();
      return;
    }

    setState(() => _isTrackingStarting = true);
    final error = await _locationService.startTracking();
    if (mounted) {
      setState(() => _isTrackingStarting = false);
    }
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
    final riderPoint = _riderPoint;
    final deliveryMarkers = _deliveryMarkers;
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
              isStarting: _isTrackingStarting,
              statusMessage: _locationService.statusMessage,
              color: color,
              onToggle: _toggleTracking,
            ),
            const SizedBox(height: 18),
            _OsmTrackingMap(
              mapController: _mapController,
              riderPoint: riderPoint,
              deliveryMarkers: deliveryMarkers,
              isTracking: isTracking,
              onMapReady: () {
                _mapReady = true;
                _moveMapToBestCenter();
              },
            ),
            const SizedBox(height: 18),
            _LocationDetails(position: position),
            const SizedBox(height: 18),
            _DeliveryLocationSummary(
              isLoading: _isDeliveriesLoading,
              deliveries: _deliveries,
              mappedMarkerCount: deliveryMarkers.length,
              onRefresh: _loadDeliveries,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final bool isTracking;
  final bool isStarting;
  final String statusMessage;
  final Color color;
  final VoidCallback onToggle;

  const _StatusPanel({
    required this.isTracking,
    required this.isStarting,
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
              onPressed: isStarting ? null : onToggle,
              icon: isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      isTracking
                          ? Icons.stop_circle_outlined
                          : Icons.gps_fixed,
                    ),
              label: Text(
                isStarting
                    ? 'Starting...'
                    : isTracking
                    ? 'Stop Tracking'
                    : 'Start Tracking',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isTracking ? _successGreen : _brandOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _brandOrange.withValues(alpha: 0.55),
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

class _OsmTrackingMap extends StatelessWidget {
  final MapController mapController;
  final LatLng? riderPoint;
  final List<_DeliveryMarker> deliveryMarkers;
  final bool isTracking;
  final VoidCallback onMapReady;

  const _OsmTrackingMap({
    required this.mapController,
    required this.riderPoint,
    required this.deliveryMarkers,
    required this.isTracking,
    required this.onMapReady,
  });

  @override
  Widget build(BuildContext context) {
    final center =
        riderPoint ?? deliveryMarkers.firstOrNull?.point ?? _defaultCenter;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 300,
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: riderPoint == null && deliveryMarkers.isEmpty
                    ? 12
                    : 15,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: onMapReady,
              ),
              children: [
                _osmTileLayer(),
                MarkerLayer(markers: _markers()),
              ],
            ),
            const Positioned(left: 8, bottom: 8, child: _MapCredit()),
            Positioned(
              right: 8,
              top: 8,
              child: _MapIconButton(
                icon: Icons.fullscreen,
                tooltip: 'Open fullscreen map',
                onTap: () => _openFullScreenMap(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _markers() {
    return [
      if (riderPoint != null)
        Marker(
          point: riderPoint!,
          width: 48,
          height: 48,
          child: const _MapMarker(
            color: _successGreen,
            icon: Icons.navigation,
            label: 'You',
          ),
        ),
      ...deliveryMarkers.map(
        (marker) => Marker(
          point: marker.point,
          width: 54,
          height: 54,
          child: _MapMarker(
            color: marker.color,
            icon: marker.icon,
            label: marker.label,
          ),
        ),
      ),
    ];
  }

  void _openFullScreenMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenOsmMap(
          riderPoint: riderPoint,
          deliveryMarkers: deliveryMarkers,
          isTracking: isTracking,
        ),
      ),
    );
  }
}

class _FullScreenOsmMap extends StatefulWidget {
  final LatLng? riderPoint;
  final List<_DeliveryMarker> deliveryMarkers;
  final bool isTracking;

  const _FullScreenOsmMap({
    required this.riderPoint,
    required this.deliveryMarkers,
    required this.isTracking,
  });

  @override
  State<_FullScreenOsmMap> createState() => _FullScreenOsmMapState();
}

class _FullScreenOsmMapState extends State<_FullScreenOsmMap> {
  final _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center =
        widget.riderPoint ??
        widget.deliveryMarkers.firstOrNull?.point ??
        _defaultCenter;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom:
                  widget.riderPoint == null && widget.deliveryMarkers.isEmpty
                  ? 12
                  : 15,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              _osmTileLayer(),
              MarkerLayer(markers: _markers()),
            ],
          ),
          const Positioned(left: 12, bottom: 12, child: _MapCredit()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Delivery Map',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _MapIconButton(
                    icon: Icons.close,
                    tooltip: 'Close fullscreen map',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _markers() {
    return [
      if (widget.riderPoint != null)
        Marker(
          point: widget.riderPoint!,
          width: 48,
          height: 48,
          child: const _MapMarker(
            color: _successGreen,
            icon: Icons.navigation,
            label: 'You',
          ),
        ),
      ...widget.deliveryMarkers.map(
        (marker) => Marker(
          point: marker.point,
          width: 54,
          height: 54,
          child: _MapMarker(
            color: marker.color,
            icon: marker.icon,
            label: marker.label,
          ),
        ),
      ),
    ];
  }
}

TileLayer _osmTileLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.example.sc_courier',
    maxNativeZoom: 19,
  );
}

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

class _MapCredit extends StatelessWidget {
  const _MapCredit();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '© OpenStreetMap',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _MapMarker({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          Container(
            width: 3,
            height: 8,
            color: color,
          ),
        ],
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

class _DeliveryLocationSummary extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> deliveries;
  final int mappedMarkerCount;
  final VoidCallback onRefresh;

  const _DeliveryLocationSummary({
    required this.isLoading,
    required this.deliveries,
    required this.mappedMarkerCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('Parcel Locations')),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, color: _textMuted),
                tooltip: 'Refresh deliveries',
              ),
            ],
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(color: _brandOrange),
              ),
            )
          else if (deliveries.isEmpty)
            const _MutedMessage('No active parcel locations assigned.')
          else ...[
            Text(
              '$mappedMarkerCount map markers from ${deliveries.length} active deliveries',
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ...deliveries.take(4).map(_DeliveryAddressRow.new),
            if (deliveries.length > 4)
              Text(
                '+${deliveries.length - 4} more deliveries',
                style: const TextStyle(color: _textMuted, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }
}

class _DeliveryAddressRow extends StatelessWidget {
  final Map<String, dynamic> delivery;

  const _DeliveryAddressRow(this.delivery);

  @override
  Widget build(BuildContext context) {
    final pickup = delivery['pickup_address']?.toString() ?? 'Pickup not set';
    final dropoff = delivery['delivery_address']?.toString() ?? 'Dropoff not set';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompactAddress(
            icon: Icons.inventory_2_outlined,
            color: _pickupBlue,
            label: 'Pickup',
            value: pickup,
          ),
          const SizedBox(height: 6),
          _CompactAddress(
            icon: Icons.location_on_outlined,
            color: _dropoffPurple,
            label: 'Dropoff',
            value: dropoff,
          ),
        ],
      ),
    );
  }
}

class _CompactAddress extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _CompactAddress({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            color: _textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _MutedMessage extends StatelessWidget {
  final String message;

  const _MutedMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _textMuted, fontSize: 13),
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

class _DeliveryMarker {
  final LatLng point;
  final String label;
  final String address;
  final Color color;
  final IconData icon;

  const _DeliveryMarker({
    required this.point,
    required this.label,
    required this.address,
    required this.color,
    required this.icon,
  });
}
