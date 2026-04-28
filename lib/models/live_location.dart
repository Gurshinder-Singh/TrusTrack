import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

// Model representing a user's live location
class LiveLocation {
  final String uid;
  final String name;
  final String initials;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  const LiveLocation({
    required this.uid,
    required this.name,
    required this.initials,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  // Convert object to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'initials': initials,
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // Create object from Firestore data
  factory LiveLocation.fromMap(Map<String, dynamic> map) {
    final updatedAt = map['updatedAt'];

    return LiveLocation(
      uid: (map['uid'] ?? '').toString(),
      name: (map['name'] ?? 'Unknown').toString(),
      initials: (map['initials'] ?? '?').toString(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
    );
  }
}
