import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/sos_alert.dart';

class GlobalSosEvent {
  final String circleCode;
  final SosAlert alert;

  const GlobalSosEvent({
    required this.circleCode,
    required this.alert,
  });
}

class GlobalSosService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _circlesSub;

  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _sosSubs = {};

  final Set<String> _seenAlertIds = {};
  final _controller = StreamController<GlobalSosEvent>.broadcast();

  Stream<GlobalSosEvent> get events => _controller.stream;

  void start() {
    _authSub?.cancel();

    _authSub = _auth.authStateChanges().listen((user) {
      _clearCircleListeners();
      _seenAlertIds.clear();

      if (user == null) return;

      _circlesSub = _db
          .collection('users')
          .doc(user.uid)
          .collection('joined_circles')
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
        final activeCodes =
            snapshot.docs.map((doc) => doc.id.trim().toUpperCase()).toSet();

        final existingCodes = _sosSubs.keys.toSet();

        for (final code in existingCodes.difference(activeCodes)) {
          _sosSubs.remove(code)?.cancel();
        }

        for (final code in activeCodes.difference(existingCodes)) {
          _listenToCircleSos(code, user.uid);
        }
      });
    });
  }

  void _listenToCircleSos(String code, String currentUid) {
    _sosSubs[code] = _db
        .collection('sessions')
        .doc(code)
        .collection('sos_alerts')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) return;

      final doc = snapshot.docs.first;
      final alert = SosAlert.fromDoc(doc);

      if (alert.senderId == currentUid) return;
      if (_seenAlertIds.contains(doc.id)) return;

      _seenAlertIds.add(doc.id);

      _controller.add(
        GlobalSosEvent(
          circleCode: code,
          alert: alert,
        ),
      );
    });
  }

  void _clearCircleListeners() {
    _circlesSub?.cancel();
    _circlesSub = null;

    for (final sub in _sosSubs.values) {
      sub.cancel();
    }

    _sosSubs.clear();
  }

  void dispose() {
    _authSub?.cancel();
    _clearCircleListeners();
    _controller.close();
  }
}
