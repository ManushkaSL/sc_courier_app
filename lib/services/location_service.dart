import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService extends ChangeNotifier {
  // Singleton
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  bool _isTracking = false;
  Position? _currentPosition;
  String _statusMessage = 'GPS tracking is off';
  StreamSubscription<Position>? _positionStream;

  bool get isTracking => _isTracking;
  Position? get currentPosition => _currentPosition;
  String get statusMessage => _statusMessage;

  /// Returns null if permission is granted, otherwise a reason string.
  Future<String?> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled on this device.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Enable it in device settings.';
    }
    return null;
  }

  /// Starts GPS tracking. Returns an error message on failure, null on success.
  Future<String?> startTracking() async {
    final error = await _ensurePermission();
    if (error != null) {
      _statusMessage = error;
      notifyListeners();
      return error;
    }

    _isTracking = true;
    _statusMessage = 'Getting location…';
    notifyListeners();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (position) {
            _currentPosition = position;
            _statusMessage =
                '${position.latitude.toStringAsFixed(5)}, '
                '${position.longitude.toStringAsFixed(5)}';
            notifyListeners();
          },
          onError: (e) {
            _isTracking = false;
            _statusMessage = 'Location error: $e';
            notifyListeners();
          },
        );

    return null;
  }

  Future<void> stopTracking() async {
    await _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    _currentPosition = null;
    _statusMessage = 'GPS tracking is off';
    notifyListeners();
  }

  /// Opens the device app-settings page for manual permission grant.
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the device location-settings page.
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
