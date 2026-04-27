import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/live_location.dart';
import '../models/person.dart';
import '../models/session.dart';
import 'location_service.dart';
import 'session_service.dart';

// Syncs user location with active circles
class LocationSyncService {
  final LocationService _locationService = LocationService();
  final SessionService _sessionService = SessionService();

  final Set<String> _sessionCodes = {};

  Person? _me;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;

  bool _started = false;
  bool _uploading = false;

  void setUser(Person me) {
    _me = me;
  }

  Future<void> startForUser({
    required Person me,
    required List<String> sessionCodes,
    required void Function(Object error) onError,
  }) async {
    _me = me;

    _sessionCodes
      ..clear()
      ..addAll(sessionCodes.map((e) => e.trim().toUpperCase()));

    if (_sessionCodes.isEmpty) {
      stop();
      return;
    }

    final ok = await _locationService.ensurePermission();

    if (!ok) {
      onError('Location permission is not enabled.');
      return;
    }

    try {
      final position = await _locationService.getOnce();
      _lastPosition = position;
      await _uploadPositionToAllCircles(position, me);
    } catch (_) {
      onError('Could not get current location yet.');
    }

    if (_started) return;

    _started = true;

    await _positionSub?.cancel();

    _positionSub = _locationService.stream(distanceFilter: 5).listen(
      (position) async {
        _lastPosition = position;

        final currentUser = _me;
        if (currentUser == null) return;

        try {
          await _uploadPositionToAllCircles(position, currentUser);
        } catch (e) {
          onError(e);
        }
      },
      onError: (e) {
        onError('Location stream error: $e');
      },
    );
  }

  Future<void> updateCircles(List<String> sessionCodes) async {
    _sessionCodes
      ..clear()
      ..addAll(sessionCodes.map((e) => e.trim().toUpperCase()));

    if (_sessionCodes.isEmpty) {
      stop();
      return;
    }

    final me = _me;
    final last = _lastPosition;

    if (me != null && last != null) {
      await _uploadPositionToAllCircles(last, me);
    }
  }

  Future<bool> uploadCurrentLocationToCircle({
    required String code,
    required Person me,
  }) async {
    _me = me;

    final ok = await _locationService.ensurePermission();

    if (!ok) return false;

    try {
      final position = await _locationService.getOnce();
      _lastPosition = position;

      await _uploadPositionToCircle(
        code: code.trim().toUpperCase(),
        position: position,
        me: me,
      );

      return true;
    } catch (_) {
      final last = _lastPosition;

      if (last != null) {
        await _uploadPositionToCircle(
          code: code.trim().toUpperCase(),
          position: last,
          me: me,
        );

        return true;
      }

      return false;
    }
  }

  Future<bool> uploadCurrentLocationToAllCircles({Person? me}) async {
    final currentUser = me ?? _me;

    if (currentUser == null || _sessionCodes.isEmpty) return false;

    _me = currentUser;

    final ok = await _locationService.ensurePermission();

    if (!ok) return false;

    try {
      final position = await _locationService.getOnce();
      _lastPosition = position;

      await _uploadPositionToAllCircles(position, currentUser);

      return true;
    } catch (_) {
      final last = _lastPosition;

      if (last != null) {
        await _uploadPositionToAllCircles(last, currentUser);
        return true;
      }

      return false;
    }
  }

  Future<void> _uploadPositionToAllCircles(
    Position position,
    Person me,
  ) async {
    if (_uploading) return;

    _uploading = true;

    try {
      final codesSnapshot = List<String>.from(_sessionCodes);

      for (final code in codesSnapshot) {
        await _uploadPositionToCircle(
          code: code,
          position: position,
          me: me,
        );
      }
    } finally {
      _uploading = false;
    }
  }

  Future<void> _uploadPositionToCircle({
    required String code,
    required Position position,
    required Person me,
  }) async {
    final session = await _sessionService.getSessionByCode(code);

    final precision = session?.precisionMode ?? PrecisionMode.exact;

    final safeLatLng = _applyPrivacyPrecision(
      LatLng(position.latitude, position.longitude),
      precision,
    );

    final liveLocation = LiveLocation(
      uid: me.id,
      name: me.name,
      initials: me.initials,
      latitude: safeLatLng.latitude,
      longitude: safeLatLng.longitude,
      updatedAt: DateTime.now(),
    );

    await _sessionService.uploadLocation(
      code: code,
      location: liveLocation,
    );
  }

  LatLng _applyPrivacyPrecision(LatLng point, PrecisionMode mode) {
    switch (mode) {
      case PrecisionMode.exact:
        return point;

      case PrecisionMode.street:
        return _roundLocation(point, 4);

      case PrecisionMode.area:
        return _roundLocation(point, 3);

      case PrecisionMode.city:
        return _roundLocation(point, 2);
    }
  }

  LatLng _roundLocation(LatLng point, int decimals) {
    final factor = pow(10, decimals).toDouble();

    return LatLng(
      (point.latitude * factor).round() / factor,
      (point.longitude * factor).round() / factor,
    );
  }

  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _sessionCodes.clear();
    _started = false;
    _uploading = false;
  }
}
