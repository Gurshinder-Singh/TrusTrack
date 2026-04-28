import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isRoadRoute;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isRoadRoute,
  });

  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get durationText {
    final minutes = (durationSeconds / 60).round();

    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }
}

class RouteService {
  final Distance _distance = const Distance();

  Future<RouteResult> getRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 8),
          );

      if (response.statusCode != 200) {
        return _fallbackRoute(from: from, to: to);
      }

      final data = jsonDecode(response.body);

      if (data['code'] != 'Ok') {
        return _fallbackRoute(from: from, to: to);
      }

      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) {
        return _fallbackRoute(from: from, to: to);
      }

      final route = routes.first;
      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();
      final coordinates = route['geometry']['coordinates'] as List;

      final points = coordinates.map((coord) {
        final lng = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        return LatLng(lat, lng);
      }).toList();

      return RouteResult(
        points: points,
        distanceMeters: distance,
        durationSeconds: duration,
        isRoadRoute: true,
      );
    } catch (_) {
      return _fallbackRoute(from: from, to: to);
    }
  }

  RouteResult _fallbackRoute({
    required LatLng from,
    required LatLng to,
  }) {
    final meters = _distance.as(LengthUnit.Meter, from, to);

    // Simple walking estimate: 5 km/h.
    final seconds = meters / 1.3889;

    return RouteResult(
      points: [from, to],
      distanceMeters: meters,
      durationSeconds: seconds,
      isRoadRoute: false,
    );
  }
}
