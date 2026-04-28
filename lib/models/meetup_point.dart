import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

// Model representing a meetup location
class MeetupPoint {
  final String name;
  final double latitude;
  final double longitude;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;

  const MeetupPoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  // Convert object to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // Create object from Firestore data
  factory MeetupPoint.fromMap(Map<String, dynamic> map) {
    final createdAt = map['createdAt'];

    return MeetupPoint(
      name: (map['name'] ?? 'Meet up point').toString(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      createdBy: (map['createdBy'] ?? '').toString(),
      createdByName: (map['createdByName'] ?? '').toString(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}
