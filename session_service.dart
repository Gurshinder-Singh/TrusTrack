import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/live_location.dart';
import '../models/meetup_point.dart';
import '../models/person.dart';
import '../models/place.dart';
import '../models/session.dart';
import '../models/sos_alert.dart';

// Handles circle sessions and Firestore data
class SessionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();

    final part1 =
        List.generate(2, (_) => chars[r.nextInt(chars.length)]).join();

    final part2 =
        List.generate(5, (_) => chars[r.nextInt(chars.length)]).join();

    return 'CL-$part1$part2';
  }

  String _cleanCode(String code) {
    final value = code.trim().toUpperCase().replaceAll(' ', '');

    if (value.startsWith('CL-')) return value;

    if (value.startsWith('CL') && value.length > 2) {
      return 'CL-${value.substring(2)}';
    }

    return value;
  }

  bool _isExpired(ShareSession session) {
    final endsAt = session.endsAt;
    if (endsAt == null) return false;
    return DateTime.now().isAfter(endsAt);
  }

  Future<String> createSession({
    required Person host,
    required String circleName,
    required PrecisionMode precisionMode,
    required SharePurpose purpose,
    Place? destination,
    DateTime? endsAt,
  }) async {
    final code = _generateCode();

    final session = ShareSession(
      code: code,
      name: circleName.trim().isEmpty ? 'My Circle' : circleName.trim(),
      hostId: host.id,
      hostName: host.name,
      createdAt: DateTime.now(),
      endsAt: endsAt,
      precisionMode: precisionMode,
      purpose: purpose,
      destination: destination,
      isActive: true,
    );

    final sessionRef = _db.collection('sessions').doc(code);

    final joinedRef = _db
        .collection('users')
        .doc(host.id)
        .collection('joined_circles')
        .doc(code);

    await sessionRef.set(session.toMap()).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw Exception('Could not save session document.');
      },
    );

    await sessionRef.collection('members').doc(host.id).set({
      ...host.toMap(),
      'joinedAt': FieldValue.serverTimestamp(),
      'isHost': true,
    }).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw Exception('Could not save member document.');
      },
    );

    await joinedRef.set({
      ...session.toMap(),
      'joinedAt': FieldValue.serverTimestamp(),
      'isHost': true,
    }).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw Exception('Could not save joined circle document.');
      },
    );

    return code;
  }

  Future<ShareSession?> getSessionByCode(String code) async {
    final cleanCode = _cleanCode(code);

    final doc = await _db.collection('sessions').doc(cleanCode).get();

    if (!doc.exists || doc.data() == null) return null;

    final session = ShareSession.fromMap(doc.data()!);

    if (!session.isActive || _isExpired(session)) {
      return null;
    }

    return session;
  }

  Future<bool> joinSession({
    required String code,
    required Person person,
  }) async {
    final cleanCode = _cleanCode(code);

    final doc = await _db.collection('sessions').doc(cleanCode).get();

    if (!doc.exists || doc.data() == null) return false;

    final session = ShareSession.fromMap(doc.data()!);

    if (!session.isActive || _isExpired(session)) return false;

    final sessionRef = _db.collection('sessions').doc(cleanCode);

    final joinedRef = _db
        .collection('users')
        .doc(person.id)
        .collection('joined_circles')
        .doc(cleanCode);

    final batch = _db.batch();

    batch.set(
      sessionRef.collection('members').doc(person.id),
      {
        ...person.toMap(),
        'joinedAt': FieldValue.serverTimestamp(),
        'isHost': session.hostId == person.id,
      },
      SetOptions(merge: true),
    );

    batch.set(
      joinedRef,
      {
        ...session.toMap(),
        'joinedAt': FieldValue.serverTimestamp(),
        'isHost': session.hostId == person.id,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    return true;
  }

  Future<void> leaveSession({
    required String code,
    required String uid,
  }) async {
    final cleanCode = _cleanCode(code);
    final sessionRef = _db.collection('sessions').doc(cleanCode);

    final batch = _db.batch();

    batch.delete(sessionRef.collection('members').doc(uid));
    batch.delete(sessionRef.collection('locations').doc(uid));

    batch.delete(
      _db
          .collection('users')
          .doc(uid)
          .collection('joined_circles')
          .doc(cleanCode),
    );

    await batch.commit();
  }

  Future<void> endSession(String code) async {
    final cleanCode = _cleanCode(code);
    final sessionRef = _db.collection('sessions').doc(cleanCode);

    final membersSnap = await sessionRef.collection('members').get();

    final batch = _db.batch();

    batch.set(
      sessionRef,
      {
        'isActive': false,
        'endedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    for (final member in membersSnap.docs) {
      final joinedRef = _db
          .collection('users')
          .doc(member.id)
          .collection('joined_circles')
          .doc(cleanCode);

      batch.set(
        joinedRef,
        {
          'isActive': false,
          'endedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> cleanupExpiredUserCircles(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('joined_circles')
        .where('isActive', isEqualTo: true)
        .get();

    for (final doc in snap.docs) {
      final session = ShareSession.fromMap(doc.data());

      if (_isExpired(session)) {
        await endSession(session.code);
      }
    }
  }

  Stream<List<ShareSession>> streamUserCircles(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('joined_circles')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final circles = snapshot.docs
          .map((doc) => ShareSession.fromMap(doc.data()))
          .where((circle) => circle.isActive && !_isExpired(circle))
          .toList();

      circles.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return circles;
    });
  }

  Stream<ShareSession?> streamSession(String code) {
    final cleanCode = _cleanCode(code);

    return _db.collection('sessions').doc(cleanCode).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;

      return ShareSession.fromMap(doc.data()!);
    });
  }

  Stream<List<Person>> streamMembers(String code) {
    final cleanCode = _cleanCode(code);

    return _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('members')
        .snapshots()
        .map((snapshot) {
      final members =
          snapshot.docs.map((doc) => Person.fromMap(doc.data())).toList();

      members.sort((a, b) => a.name.compareTo(b.name));

      return members;
    });
  }

  Stream<List<LiveLocation>> streamLocations(String code) {
    final cleanCode = _cleanCode(code);

    return _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('locations')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => LiveLocation.fromMap(doc.data()))
              .toList(),
        );
  }

  Future<void> uploadLocation({
    required String code,
    required LiveLocation location,
  }) async {
    final cleanCode = _cleanCode(code);

    await _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('locations')
        .doc(location.uid)
        .set(location.toMap(), SetOptions(merge: true));
  }

  Future<void> sendSos({
    required String code,
    required Person sender,
    required String message,
    required double? latitude,
    required double? longitude,
  }) async {
    final cleanCode = _cleanCode(code);

    await _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('sos_alerts')
        .add({
      'senderId': sender.id,
      'senderName': sender.name,
      'message': message.trim().isEmpty ? 'SOS alert' : message.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<SosAlert>> streamSosAlerts(String code) {
    final cleanCode = _cleanCode(code);

    return _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('sos_alerts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SosAlert.fromMap(doc.data(), id: doc.id))
              .toList(),
        );
  }

  Future<void> setMeetupPoint({
    required String code,
    required MeetupPoint meetupPoint,
  }) async {
    final cleanCode = _cleanCode(code);

    await _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('meetup')
        .doc('current')
        .set(meetupPoint.toMap(), SetOptions(merge: true));
  }

  Future<void> clearMeetupPoint(String code) async {
    final cleanCode = _cleanCode(code);

    await _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('meetup')
        .doc('current')
        .delete();
  }

  Stream<MeetupPoint?> streamMeetupPoint(String code) {
    final cleanCode = _cleanCode(code);

    return _db
        .collection('sessions')
        .doc(cleanCode)
        .collection('meetup')
        .doc('current')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return MeetupPoint.fromMap(doc.data()!);
    });
  }
}
