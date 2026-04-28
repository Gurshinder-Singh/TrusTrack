import 'package:latlong2/latlong.dart';

class Place {
  final String id;
  final String name;
  final LatLng latLng;
  final double radiusMeters;

  const Place({
    required this.id,
    required this.name,
    required this.latLng,
    required this.radiusMeters,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lat': latLng.latitude,
      'lng': latLng.longitude,
      'radiusMeters': radiusMeters,
    };
  }

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      latLng: LatLng(
        (map['lat'] as num).toDouble(),
        (map['lng'] as num).toDouble(),
      ),
      radiusMeters: (map['radiusMeters'] as num).toDouble(),
    );
  }
}
