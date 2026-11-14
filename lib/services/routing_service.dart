import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final String? summary;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.summary,
  });

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toStringAsFixed(0)} m';
  }

  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMins = minutes % 60;
      return '${hours}h ${remainingMins}m';
    }
    return '$minutes min';
  }
}

class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  static final Map<String, LatLng> _knownTowns = {
    'wellawatta': const LatLng(6.8741, 79.8606),
    'wellawatte': const LatLng(6.8741, 79.8606),
    'colombo': const LatLng(6.9271, 79.8612),
    'kollupitiya': const LatLng(6.8999, 79.8530),
    'colpetty': const LatLng(6.8999, 79.8530),
    'bambalapitiya': const LatLng(6.8905, 79.8553),
    'dehiwala': const LatLng(6.8511, 79.8659),
    'mount lavinia': const LatLng(6.8375, 79.8647),
    'moratuwa': const LatLng(6.7730, 79.8816),
    'panadura': const LatLng(6.7130, 79.9074),
    'rajagiriya': const LatLng(6.9088, 79.8973),
    'battaramulla': const LatLng(6.8997, 79.9192),
    'nugegoda': const LatLng(6.8649, 79.8997),
    'maharagama': const LatLng(6.8480, 79.9267),
    'kotte': const LatLng(6.8906, 79.9015),
    'pettah': const LatLng(6.9366, 79.8504),
    'fort': const LatLng(6.9344, 79.8428),
    'maradana': const LatLng(6.9279, 79.8697),
    'kandy': const LatLng(7.2906, 80.6337),
    'galle': const LatLng(6.0535, 80.2210),
    'jaffna': const LatLng(9.6615, 80.0255),
    'negombo': const LatLng(7.2008, 79.8736),
    'gampaha': const LatLng(7.0840, 79.9937),
    'kurunegala': const LatLng(7.4863, 80.3623),
    'matara': const LatLng(5.9549, 80.5550),
    'anuradhapura': const LatLng(8.3114, 80.4037),
    'trincomalee': const LatLng(8.5874, 81.2152),
    'batticaloa': const LatLng(7.7310, 81.6747),
    'ratnapura': const LatLng(6.6828, 80.4034),
    'badulla': const LatLng(6.9934, 81.0550),
    'kalutara': const LatLng(6.5854, 79.9607),
  };

  /// Geocodes a text address string to LatLng.
  /// First checks local Sri Lanka town dictionary, then queries OpenStreetMap Nominatim.
  Future<LatLng?> geocodeAddress(String rawAddress) async {
    final clean = rawAddress.trim().toLowerCase();
    if (clean.isEmpty) return null;

    for (final entry in _knownTowns.entries) {
      if (clean.contains(entry.key)) {
        return entry.value;
      }
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent('$rawAddress, Sri Lanka')}&limit=1',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'SC_Courier_Rider_App/1.0',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final lat = double.tryParse(first['lat']?.toString() ?? '');
          final lon = double.tryParse(first['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return null;
  }

  /// Fetches an actual road-based route using OSRM.
  /// Works across Flutter Web, Android, iOS and Desktop using http client.
  Future<RouteResult?> getRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': 'SC_Courier_Rider_App/1.0',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('OSRM routing request failed: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        return null;
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List<dynamic>?;

      if (coordinates == null || coordinates.isEmpty) {
        return null;
      }

      final points = <LatLng>[];
      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          final lng = (coord[0] as num).toDouble();
          final lat = (coord[1] as num).toDouble();
          points.add(LatLng(lat, lng));
        }
      }

      final distance = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0.0;
      final legs = route['legs'] as List<dynamic>?;
      final summary = legs?.firstOrNull?['summary'] as String?;

      return RouteResult(
        points: points,
        distanceMeters: distance,
        durationSeconds: duration,
        summary: summary,
      );
    } catch (e) {
      debugPrint('Error fetching route from OSRM: $e');
      return null;
    }
  }
}
