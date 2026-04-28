import 'package:cloud_firestore/cloud_firestore.dart';

class SosAlert {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  const SosAlert({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory SosAlert.fromDoc(
    dynamic doc, [
    Map<String, dynamic>? data,
  ]) {
    if (doc is QueryDocumentSnapshot<Map<String, dynamic>>) {
      return SosAlert.fromMap(doc.data(), id: doc.id);
    }

    if (doc is DocumentSnapshot<Map<String, dynamic>>) {
      return SosAlert.fromMap(doc.data() ?? {}, id: doc.id);
    }

    if (doc is String) {
      return SosAlert.fromMap(data ?? {}, id: doc);
    }

    return SosAlert.fromMap(data ?? {});
  }

  factory SosAlert.fromMap(
    Map<String, dynamic> map, {
    String id = '',
  }) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      return DateTime.tryParse(value.toString()) ?? DateTime.now();
    }

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return SosAlert(
      id: id,
      senderId: (map['senderId'] ?? '').toString(),
      senderName: (map['senderName'] ?? 'Unknown').toString(),
      message: (map['message'] ?? 'SOS alert').toString(),
      latitude: parseDouble(map['latitude']),
      longitude: parseDouble(map['longitude']),
      createdAt: parseDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
