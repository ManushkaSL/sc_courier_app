import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../services/supabase_service.dart';

const _brandOrange = Color(0xFFF97316);
const _successGreen = Color(0xFF4ADE80);
const _warning = Color(0xFFFFB020);
const _pickupBlue = Color(0xFF38BDF8);
const _dropoffPurple = Color(0xFFA78BFA);
const _appBg = Color(0xFF151515);
const _surface = Color(0xFF222222);
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
  final _routingService = RoutingService();
  final _mapController = MapController();

  List<Map<String, dynamic>> _deliveries = [];
  Map<String, dynamic>? _selectedDelivery;
  RouteResult? _currentRoute;
  bool _isCalculatingRoute = false;
  LatLng? _lastRouteRiderPoint;
  bool _didLoadArguments = false;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadArguments) {
      _didLoadArguments = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['delivery'] is Map) {
        _selectedDelivery = Map<String, dynamic>.from(args['delivery']);
      }
    }
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
        if (_selectedDelivery == null && _deliveries.isNotEmpty) {
          _selectedDelivery = _deliveries.firstWhere(
            (d) => ['accepted', 'picked_up', 'in_transit'].contains(d['status']),
            orElse: () => _deliveries.first,
          );
        }
      });
      _moveMapToBestCenter();
      _calculateNavigationRoute();
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
      'assigned',
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
    _calculateNavigationRoute();
  }

  bool get _isHeadingToPickup {
    final status = (_selectedDelivery?['status'] ?? '').toString().toLowerCase();
    return status == 'pending' || status == 'assigned' || status == 'accepted';
  }

  LatLng? _getPickupPoint(Map<String, dynamic> delivery) {
    return _coordinateFromDelivery(
      delivery,
      latKeys: const [
        'pickup_latitude',
        'pickup_lat',
        'pickupLat',
        'pickup_location_latitude',
        'pick_latitude',
        'pick_lat',
        'origin_latitude',
        'origin_lat',
      ],
      lngKeys: const [
        'pickup_longitude',
        'pickup_lng',
        'pickupLng',
        'pickup_location_longitude',
        'pick_longitude',
        'pick_lng',
        'origin_longitude',
        'origin_lng',
      ],
      jsonKeys: const ['pickup_location', 'pickup_coordinates'],
    );
  }

  LatLng? _getDropoffPoint(Map<String, dynamic> delivery) {
    return _coordinateFromDelivery(
      delivery,
      latKeys: const [
        'delivery_latitude',
        'delivery_lat',
        'dropoff_latitude',
        'dropoff_lat',
        'drop_lat',
        'drop_latitude',
        'dropLat',
        'destination_latitude',
        'destination_lat',
      ],
      lngKeys: const [
        'delivery_longitude',
        'delivery_lng',
        'dropoff_longitude',
        'dropoff_lng',
        'drop_lng',
        'drop_longitude',
        'dropLng',
        'destination_longitude',
        'destination_lng',
      ],
      jsonKeys: const [
        'delivery_location',
        'delivery_coordinates',
        'dropoff_location',
        'drop_location',
      ],
    );
  }

  LatLng? get _currentNavigationTarget {
    if (_selectedDelivery == null) return null;
    return _isHeadingToPickup
        ? _getPickupPoint(_selectedDelivery!)
        : _getDropoffPoint(_selectedDelivery!);
  }

  String get _currentDestinationLabel {
    return _isHeadingToPickup ? 'Pickup Location' : 'Drop-off Destination';
  }

  String get _currentDestinationAddress {
    if (_selectedDelivery == null) return 'No destination selected';
    return _isHeadingToPickup
        ? _textValue(_selectedDelivery!, const ['pickup_address', 'pick_location', 'pickLocation'])
        : _textValue(_selectedDelivery!, const ['delivery_address', 'drop_address', 'drop_location', 'dropLocation']);
  }

  Future<void> _calculateNavigationRoute() async {
    final rider = _riderPoint;
    var target = _currentNavigationTarget;

    // Fallback: If target coordinates are not yet set in DB, resolve from text address
    if (target == null && _selectedDelivery != null) {
      final addr = _currentDestinationAddress;
      if (addr.isNotEmpty && addr != 'Address not available' && addr != 'No destination selected') {
        final geocoded = await _routingService.geocodeAddress(addr);
        if (geocoded != null && mounted) {
          setState(() {
            if (_isHeadingToPickup) {
              _selectedDelivery!['pickup_latitude'] = geocoded.latitude;
              _selectedDelivery!['pickup_longitude'] = geocoded.longitude;
              _selectedDelivery!['pickup_lat'] = geocoded.latitude;
              _selectedDelivery!['pickup_lng'] = geocoded.longitude;
            } else {
              _selectedDelivery!['delivery_latitude'] = geocoded.latitude;
              _selectedDelivery!['delivery_longitude'] = geocoded.longitude;
              _selectedDelivery!['drop_lat'] = geocoded.latitude;
              _selectedDelivery!['drop_lng'] = geocoded.longitude;
            }
          });
          target = geocoded;
          _moveMapToBestCenter();
        }
      }
    }

    if (rider == null || target == null || _isCalculatingRoute) return;

    if (_lastRouteRiderPoint != null && _currentRoute != null) {
      final distanceMoved = const Distance().as(LengthUnit.Meter, _lastRouteRiderPoint!, rider);
      if (distanceMoved < 35) return;
    }

    _isCalculatingRoute = true;
    try {
      final route = await _routingService.getRoute(start: rider, destination: target);
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _lastRouteRiderPoint = rider;
          _isCalculatingRoute = false;
        });
        _moveMapToBestCenter();
      }
    } catch (_) {
      if (mounted) _isCalculatingRoute = false;
    }
  }

  Future<void> _markParcelCollected() async {
    final id = _selectedDelivery?['id']?.toString();
    if (id == null) return;
    await _supabaseService.updateDeliveryStatus(id, 'picked_up');
    if (!mounted) return;
    setState(() {
      _selectedDelivery?['status'] = 'picked_up';
      _currentRoute = null;
      _lastRouteRiderPoint = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Parcel picked up! Navigation switched to Drop-off destination.'),
        backgroundColor: _pickupBlue,
      ),
    );
    _calculateNavigationRoute();
  }

  Future<void> _completeActiveDelivery() async {
    final id = _selectedDelivery?['id']?.toString();
    if (id == null) return;
    await _supabaseService.updateDeliveryStatus(id, 'completed');
    await _locationService.stopTracking();
    if (!mounted) return;
    setState(() {
      _selectedDelivery?['status'] = 'completed';
      _currentRoute = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delivery completed successfully! Location tracking stopped.'),
        backgroundColor: _successGreen,
      ),
    );
  }

  Future<void> _cancelActiveDelivery() async {
    final id = _selectedDelivery?['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Cancel Assignment?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to cancel this delivery assignment? Live tracking and navigation will stop.',
          style: TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _supabaseService.updateDeliveryStatus(id, 'cancelled');
      await _locationService.stopTracking();
      if (!mounted) return;
      setState(() {
        _selectedDelivery?['status'] = 'cancelled';
        _currentRoute = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery assignment cancelled.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _moveMapToBestCenter() {
    if (!_mapReady) return;
    final rider = _riderPoint;
    final target = _currentNavigationTarget;
    if (rider != null && target != null) {
      final bounds = LatLngBounds.fromPoints([rider, target]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 80),
        ),
      );
      return;
    }
    final center = rider ?? target ?? _deliveryMarkers.firstOrNull?.point;
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
    final list = <Map<String, dynamic>>[..._deliveries];
    if (_selectedDelivery != null) {
      final selId = _selectedDelivery!['id']?.toString();
      final exists = list.any((d) => d['id']?.toString() == selId);
      if (!exists) {
        list.add(_selectedDelivery!);
      }
    }
    for (final delivery in list) {
      final pickup = _getPickupPoint(delivery);
      if (pickup != null) {
        markers.add(
          _DeliveryMarker(
            point: pickup,
            label: 'Pickup',
            address: _textValue(delivery, ['pickup_address', 'pick_location']),
            color: _pickupBlue,
            icon: Icons.inventory_2_outlined,
          ),
        );
      }

      final dropoff = _getDropoffPoint(delivery);
      if (dropoff != null) {
        markers.add(
          _DeliveryMarker(
            point: dropoff,
            label: 'Dropoff',
            address: _textValue(delivery, ['delivery_address', 'drop_address', 'drop_location']),
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
    if (directLat != null && directLng != null) {
      return LatLng(directLat, directLng);
    }

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
              currentRoute: _currentRoute,
              destinationLabel: _currentDestinationLabel,
              destinationAddress: _currentDestinationAddress,
              isHeadingToPickup: _isHeadingToPickup,
              onPickup: _markParcelCollected,
              onComplete: _completeActiveDelivery,
              onCancel: _cancelActiveDelivery,
              onMapReady: () {
                _mapReady = true;
                _moveMapToBestCenter();
              },
            ),
            if (_selectedDelivery != null) ...[
              const SizedBox(height: 14),
              _ActiveDeliveryControlCard(
                delivery: _selectedDelivery!,
                isHeadingToPickup: _isHeadingToPickup,
                route: _currentRoute,
                onPickup: _markParcelCollected,
                onComplete: _completeActiveDelivery,
                onCancel: _cancelActiveDelivery,
              ),
            ],
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
                      isTracking
                          ? 'GPS tracking active'
                          : 'GPS tracking is off',
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
                      isTracking ? Icons.stop_circle_outlined : Icons.gps_fixed,
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
  final RouteResult? currentRoute;
  final String? destinationLabel;
  final String? destinationAddress;
  final bool isHeadingToPickup;
  final VoidCallback? onPickup;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;

  const _OsmTrackingMap({
    required this.mapController,
    required this.riderPoint,
    required this.deliveryMarkers,
    required this.isTracking,
    required this.onMapReady,
    this.currentRoute,
    this.destinationLabel,
    this.destinationAddress,
    this.isHeadingToPickup = true,
    this.onPickup,
    this.onComplete,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final center =
        riderPoint ?? deliveryMarkers.firstOrNull?.point ?? _defaultCenter;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 350,
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
                if (currentRoute != null && currentRoute!.points.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      // Outer glow/shadow
                      Polyline(
                        points: currentRoute!.points,
                        strokeWidth: 8.0,
                        color: const Color(0xFF1E3A8A).withValues(alpha: 0.6),
                      ),
                      // Main road line
                      Polyline(
                        points: currentRoute!.points,
                        strokeWidth: 5.0,
                        color: const Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                MarkerLayer(markers: _markers()),
              ],
            ),
            const Positioned(left: 8, bottom: 8, child: _MapCredit()),

            // Google Maps-style Navigation HUD Header (when route is active)
            if (currentRoute != null && destinationAddress != null)
              Positioned(
                left: 10,
                right: 58,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isHeadingToPickup
                          ? _pickupBlue.withValues(alpha: 0.5)
                          : _dropoffPurple.withValues(alpha: 0.5),
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (isHeadingToPickup ? _pickupBlue : _dropoffPurple)
                              .withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.navigation,
                          color: isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isHeadingToPickup ? 'HEADING TO PICKUP' : 'HEADING TO DROP-OFF',
                              style: TextStyle(
                                color: isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              destinationAddress!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${currentRoute!.formattedDistance} • ${currentRoute!.formattedDuration}',
                              style: const TextStyle(
                                color: _successGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              right: 8,
              top: 8,
              child: _MapIconButton(
                icon: Icons.fullscreen,
                tooltip: 'Open Google Maps Navigation view',
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
          width: 52,
          height: 52,
          child: const _MapMarker(
            color: _successGreen,
            icon: Icons.navigation,
            label: 'You (Moving)',
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
          currentRoute: currentRoute,
          destinationLabel: destinationLabel,
          destinationAddress: destinationAddress,
          isHeadingToPickup: isHeadingToPickup,
          onPickup: onPickup,
          onComplete: onComplete,
          onCancel: onCancel,
        ),
      ),
    );
  }
}

class _FullScreenOsmMap extends StatefulWidget {
  final LatLng? riderPoint;
  final List<_DeliveryMarker> deliveryMarkers;
  final bool isTracking;
  final RouteResult? currentRoute;
  final String? destinationLabel;
  final String? destinationAddress;
  final bool isHeadingToPickup;
  final VoidCallback? onPickup;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;

  const _FullScreenOsmMap({
    required this.riderPoint,
    required this.deliveryMarkers,
    required this.isTracking,
    this.currentRoute,
    this.destinationLabel,
    this.destinationAddress,
    this.isHeadingToPickup = true,
    this.onPickup,
    this.onComplete,
    this.onCancel,
  });

  @override
  State<_FullScreenOsmMap> createState() => _FullScreenOsmMapState();
}

class _FullScreenOsmMapState extends State<_FullScreenOsmMap> {
  final _mapController = MapController();
  RouteResult? _activeRoute;
  List<_DeliveryMarker> _markersList = [];

  @override
  void initState() {
    super.initState();
    _activeRoute = widget.currentRoute;
    _markersList = List<_DeliveryMarker>.from(widget.deliveryMarkers);
    _ensureDestinationMarker();
  }

  Future<void> _ensureDestinationMarker() async {
    final hasTarget = _markersList.any((m) =>
        widget.isHeadingToPickup ? m.label == 'Pickup' : m.label == 'Dropoff');

    if (!hasTarget && widget.destinationAddress != null && widget.destinationAddress!.isNotEmpty) {
      final geocoded = await RoutingService().geocodeAddress(widget.destinationAddress!);
      if (geocoded != null && mounted) {
        setState(() {
          _markersList.add(
            _DeliveryMarker(
              point: geocoded,
              label: widget.isHeadingToPickup ? 'Pickup' : 'Dropoff',
              address: widget.destinationAddress!,
              color: widget.isHeadingToPickup ? _pickupBlue : _dropoffPurple,
              icon: widget.isHeadingToPickup ? Icons.inventory_2_outlined : Icons.location_on_outlined,
            ),
          );
        });
        _calculateRouteIfMissing();
      }
    } else {
      _calculateRouteIfMissing();
    }
  }

  Future<void> _calculateRouteIfMissing() async {
    final target = _markersList.firstOrNull?.point;
    if (_activeRoute == null && widget.riderPoint != null && target != null) {
      final route = await RoutingService().getRoute(
        start: widget.riderPoint!,
        destination: target,
      );
      if (route != null && mounted) {
        setState(() {
          _activeRoute = route;
        });
        _fitMapBounds();
      }
    } else {
      _fitMapBounds();
    }
  }

  void _fitMapBounds() {
    final points = <LatLng>[];
    if (widget.riderPoint != null) points.add(widget.riderPoint!);
    for (final m in _markersList) {
      points.add(m.point);
    }
    if (_activeRoute != null && _activeRoute!.points.isNotEmpty) {
      points.addAll(_activeRoute!.points);
    }
    if (points.length >= 2) {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 130),
        ),
      );
    } else if (points.isNotEmpty) {
      _mapController.move(points.first, 15);
    }
  }

  void _recenterOnRider() {
    final points = <LatLng>[];
    if (widget.riderPoint != null) points.add(widget.riderPoint!);
    for (final m in _markersList) {
      points.add(m.point);
    }
    if (points.length >= 2) {
      _fitMapBounds();
    } else if (widget.riderPoint != null) {
      _mapController.move(widget.riderPoint!, 17);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center =
        widget.riderPoint ??
        _markersList.firstOrNull?.point ??
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
                  widget.riderPoint == null && _markersList.isEmpty
                  ? 12
                  : 14,
              minZoom: 3,
              maxZoom: 19,
              onMapReady: _fitMapBounds,
            ),
            children: [
              _osmTileLayer(),
              if (_activeRoute != null && _activeRoute!.points.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeRoute!.points,
                      strokeWidth: 9.0,
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.7),
                    ),
                    Polyline(
                      points: _activeRoute!.points,
                      strokeWidth: 6.0,
                      color: const Color(0xFF3B82F6),
                    ),
                  ],
                ),
              MarkerLayer(markers: _markers()),
            ],
          ),
          const Positioned(left: 12, bottom: 90, child: _MapCredit()),

          // Google Maps-Style Top Navigation Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: widget.isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (widget.isHeadingToPickup ? _pickupBlue : _dropoffPurple)
                                .withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.navigation,
                            color: widget.isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.isHeadingToPickup
                                    ? 'STAGE 1: PICKUP PARCEL'
                                    : 'STAGE 2: DELIVER TO DESTINATION',
                                style: TextStyle(
                                  color: widget.isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.destinationAddress ?? 'Destination',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_activeRoute != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  '${_activeRoute!.formattedDistance} • ${_activeRoute!.formattedDuration}',
                                  style: const TextStyle(
                                    color: _successGreen,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 3),
                                const Text(
                                  'Calculating road navigation...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          tooltip: 'Exit Navigation',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Google Maps-Style Bottom Control Bar
          Positioned(
            left: 14,
            right: 14,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'recenter_nav',
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    onPressed: _recenterOnRider,
                    tooltip: 'Recenter on me',
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: widget.isHeadingToPickup
                        ? SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onPickup?.call();
                              },
                              icon: const Icon(Icons.inventory_2_outlined, size: 20),
                              label: const Text(
                                'Mark Collected (Head to Drop)',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _pickupBlue,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          )
                        : SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onComplete?.call();
                              },
                              icon: const Icon(Icons.check_circle_outline, size: 20),
                              label: const Text(
                                'Complete Delivery',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _successGreen,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
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
          width: 52,
          height: 52,
          child: const _MapMarker(
            color: _successGreen,
            icon: Icons.navigation,
            label: 'You',
          ),
        ),
      ..._markersList.map(
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
          Container(width: 3, height: 8, color: color),
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
    final dropoff =
        delivery['delivery_address']?.toString() ?? 'Dropoff not set';

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
  const _DetailDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 18, indent: 0, color: Colors.white10);
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

class _ActiveDeliveryControlCard extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final bool isHeadingToPickup;
  final RouteResult? route;
  final VoidCallback onPickup;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _ActiveDeliveryControlCard({
    required this.delivery,
    required this.isHeadingToPickup,
    required this.route,
    required this.onPickup,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final code = delivery['tracking_code'] ?? delivery['parcel_id'] ?? delivery['id'] ?? 'N/A';
    final recipient = delivery['recipient_name'] ?? delivery['receiver_name'] ?? 'Recipient';
    final pickup = delivery['pickup_address'] ?? 'Pickup location';
    final drop = delivery['delivery_address'] ?? 'Drop location';

    return _SurfacePanel(
      padding: const EdgeInsets.all(16),
      borderColor: isHeadingToPickup
          ? _pickupBlue.withValues(alpha: 0.35)
          : _dropoffPurple.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isHeadingToPickup ? _pickupBlue : _dropoffPurple).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isHeadingToPickup ? 'STAGE 1: PICKUP' : 'STAGE 2: DROP-OFF',
                  style: TextStyle(
                    color: isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '#$code',
                style: const TextStyle(color: _textMuted, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isHeadingToPickup ? Icons.inventory_2_outlined : Icons.location_on_outlined,
                color: isHeadingToPickup ? _pickupBlue : _dropoffPurple,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHeadingToPickup ? 'Pickup: $pickup' : 'Drop-off: $drop',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Customer: $recipient',
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (route != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alt_route, color: _successGreen, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Road Route: ${route!.formattedDistance} (${route!.formattedDuration})',
                    style: const TextStyle(color: _successGreen, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: isHeadingToPickup
                    ? SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: onPickup,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Mark Collected'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _pickupBlue,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: onComplete,
                          icon: const Icon(Icons.flag_outlined, size: 18),
                          label: const Text('Complete Delivery'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _successGreen,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
