import 'package:cloud_firestore/cloud_firestore.dart';
import 'place.dart';

enum PrecisionMode { exact, street, area, city }

enum SharePurpose { general, destination }

// Model representing a sharing session
class ShareSession {
  final String code;
  final String name;
  final String hostId;
  final String hostName;
  final DateTime createdAt;
  final DateTime? endsAt;
  final PrecisionMode precisionMode;
  final SharePurpose purpose;
  final Place? destination;
  final bool isActive;

  const ShareSession({
    required this.code,
    required this.name,
    required this.hostId,
    required this.hostName,
    required this.createdAt,
    required this.endsAt,
    required this.precisionMode,
    required this.purpose,
    required this.destination,
    required this.isActive,
  });

  // Convert object to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'hostId': hostId,
      'hostName': hostName,
      'createdAt': Timestamp.fromDate(createdAt),
      'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
      'precisionMode': precisionMode.name,
      'purpose': purpose.name,
      'destination': destination?.toMap(),
      'destinationName': destination?.name,
      'isActive': isActive,
    };
  }

  // Create object from Firestore data
  factory ShareSession.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      return DateTime.tryParse(value.toString()) ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      return DateTime.tryParse(value.toString());
    }

    final precisionName = (map['precisionMode'] ?? 'exact').toString();
    final purposeName = (map['purpose'] ?? 'general').toString();

    return ShareSession(
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? 'Circle').toString(),
      hostId: (map['hostId'] ?? '').toString(),
      hostName: (map['hostName'] ?? '').toString(),
      createdAt: parseDate(map['createdAt']),
      endsAt: parseNullableDate(map['endsAt']),
      precisionMode: PrecisionMode.values.firstWhere(
        (e) => e.name == precisionName,
        orElse: () => PrecisionMode.exact,
      ),
      purpose: SharePurpose.values.firstWhere(
        (e) => e.name == purposeName,
        orElse: () => SharePurpose.general,
      ),
      destination: map['destination'] is Map<String, dynamic>
          ? Place.fromMap(map['destination'] as Map<String, dynamic>)
          : null,
      isActive: (map['isActive'] ?? true) as bool,
    );
  }
}
