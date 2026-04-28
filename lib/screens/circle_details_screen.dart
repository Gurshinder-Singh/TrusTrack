import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/live_location.dart';
import '../models/meetup_point.dart';
import '../models/person.dart';
import '../models/session.dart';
import '../services/chat_service.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/session_service.dart';
import '../widgets/session_map.dart';

// Screen showing circle details, map, meetup point, and chat
class CircleDetailsScreen extends StatefulWidget {
  final Person me;
  final ShareSession initialCircle;

  const CircleDetailsScreen({
    super.key,
    required this.me,
    required this.initialCircle,
  });

  @override
  State<CircleDetailsScreen> createState() => _CircleDetailsScreenState();
}

class _CircleDetailsScreenState extends State<CircleDetailsScreen> {
  final _sessionService = SessionService();
  final _locationService = LocationService();
  final _geo = GeocodingService();
  final _routeService = RouteService();
  final _chatService = ChatService();

  final _meetupController = TextEditingController();
  final _messageController = TextEditingController();

  ShareSession? _circle;
  List<LiveLocation> _locations = [];
  List<Person> _members = [];

  MeetupPoint? _meetupPoint;
  List<LatLng> _routePoints = [];
  String? _routeDistanceText;
  String? _routeDurationText;
  String? _routeNote;
  bool _loadingRoute = false;

  StreamSubscription? _circleSub;
  StreamSubscription? _locSub;
  StreamSubscription? _membersSub;
  StreamSubscription? _sosSub;
  StreamSubscription? _meetupSub;
  Timer? _autoEndTimer;

  LatLng? _myLatLng;
  LatLng? _focusedLocation;
  String? _locError;

  bool _arrived = false;
  bool _arrivalDialogShown = false;
  bool _isClosing = false;
  int _routeRequestId = 0;

  @override
  void initState() {
    super.initState();

    _circle = widget.initialCircle;
    _watchCircle(widget.initialCircle.code);
    _ensureLocationPermission();
    _startAutoEndChecker();
  }

  @override
  void dispose() {
    _circleSub?.cancel();
    _locSub?.cancel();
    _membersSub?.cancel();
    _sosSub?.cancel();
    _meetupSub?.cancel();
    _autoEndTimer?.cancel();
    _meetupController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _startAutoEndChecker() {
    _autoEndTimer?.cancel();

    _autoEndTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final circle = _circle;

      if (circle == null || _isClosing) return;

      final endsAt = circle.endsAt;

      if (endsAt != null && DateTime.now().isAfter(endsAt)) {
        _closePageImmediately();

        unawaited(_sessionService.endSession(circle.code));
      }
    });
  }

  Future<void> _ensureLocationPermission() async {
    final ok = await _locationService.ensurePermission();

    if (!mounted) return;

    setState(() {
      _locError = ok ? null : 'Location permission/service not available.';
    });
  }

  // Listen to circle updates
  void _watchCircle(String code) {
    _circleSub?.cancel();
    _locSub?.cancel();
    _membersSub?.cancel();
    _sosSub?.cancel();
    _meetupSub?.cancel();

    _circleSub = _sessionService.streamSession(code).listen((circle) {
      if (!mounted || _isClosing) return;

      if (circle == null) {
        return;
      }

      final expired =
          circle.endsAt != null && DateTime.now().isAfter(circle.endsAt!);

      if (!circle.isActive || expired) {
        _safeCloseToHome();
        return;
      }

      setState(() => _circle = circle);
      _checkArrivalIfNeeded();
    });

    _locSub = _sessionService.streamLocations(code).listen((locations) {
      if (!mounted || _isClosing) return;

      setState(() {
        _locations = locations;

        final myMatches = locations.where((e) => e.uid == widget.me.id);

        if (myMatches.isNotEmpty) {
          _myLatLng = myMatches.first.latLng;
        }
      });

      _checkArrivalIfNeeded();

      if (_meetupPoint != null && _routePoints.isEmpty) {
        _updateRouteToMeetup();
      }
    });

    _membersSub = _sessionService.streamMembers(code).listen((members) {
      if (!mounted || _isClosing) return;
      setState(() => _members = members);
    });

    _sosSub = _sessionService.streamSosAlerts(code).listen((_) {});

    _meetupSub = _sessionService.streamMeetupPoint(code).listen((point) async {
      if (!mounted || _isClosing) return;

      setState(() {
        _meetupPoint = point;
        _routePoints = [];
        _routeDistanceText = null;
        _routeDurationText = null;
        _routeNote = null;
      });

      await _updateRouteToMeetup();
    });
  }

  void _closePageImmediately() {
    if (_isClosing || !mounted) return;

    _isClosing = true;

    Navigator.of(context).pop(true);
  }

  void _safeCloseToHome() {
    if (_isClosing || !mounted) return;

    _isClosing = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
    });
  }

  // Set meetup point
  Future<void> _setMeetupPoint() async {
    final circle = _circle;
    if (circle == null) return;

    final typed = _meetupController.text.trim();

    if (typed.isEmpty) {
      _showSnack('Enter a meetup place or address.');
      return;
    }

    _showSnack('Finding meetup point...');

    final latLng = await _geo.geocodeAddress(typed);

    if (latLng == null) {
      _showSnack('Could not find that meetup point.');
      return;
    }

    final meetup = MeetupPoint(
      name: typed,
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      createdBy: widget.me.id,
      createdByName: widget.me.name,
      createdAt: DateTime.now(),
    );

    await _sessionService.setMeetupPoint(
      code: circle.code,
      meetupPoint: meetup,
    );

    _meetupController.clear();
    _showSnack('Meetup point shared.');
  }

  Future<void> _clearMeetupPoint() async {
    final circle = _circle;
    if (circle == null) return;

    await _sessionService.clearMeetupPoint(circle.code);

    setState(() {
      _meetupPoint = null;
      _routePoints = [];
      _routeDistanceText = null;
      _routeDurationText = null;
      _routeNote = null;
      _loadingRoute = false;
    });

    _showSnack('Meetup point removed.');
  }

  // Calculate route to meetup point
  Future<void> _updateRouteToMeetup() async {
    final meetup = _meetupPoint;
    final me = _myLatLng;

    if (meetup == null || me == null || _loadingRoute) return;

    final requestId = ++_routeRequestId;

    setState(() {
      _loadingRoute = true;
      _routeNote = null;
    });

    try {
      final route = await _routeService.getRoute(
        from: me,
        to: meetup.latLng,
      );

      if (!mounted || requestId != _routeRequestId) return;

      setState(() {
        _routePoints = route.points;
        _routeDistanceText = route.distanceText;
        _routeDurationText = route.durationText;
        _routeNote =
            route.isRoadRoute ? 'Road route' : 'Estimated straight-line route';
      });
    } catch (_) {
      if (!mounted || requestId != _routeRequestId) return;

      final meters = const Distance().as(
        LengthUnit.Meter,
        me,
        meetup.latLng,
      );

      setState(() {
        _routePoints = [me, meetup.latLng];
        _routeDistanceText = meters < 1000
            ? '${meters.round()} m'
            : '${(meters / 1000).toStringAsFixed(1)} km';
        _routeDurationText = '${(meters / 83.3).round()} min';
        _routeNote = 'Estimated straight-line route';
      });
    } finally {
      if (mounted && requestId == _routeRequestId) {
        setState(() => _loadingRoute = false);
      }
    }
  }

  void _checkArrivalIfNeeded() {
    final circle = _circle;

    if (circle == null ||
        circle.purpose != SharePurpose.destination ||
        circle.destination == null ||
        _myLatLng == null ||
        _arrivalDialogShown ||
        _isClosing) {
      return;
    }

    final d = const Distance().as(
      LengthUnit.Meter,
      _myLatLng!,
      circle.destination!.latLng,
    );

    if (d <= circle.destination!.radiusMeters && !_arrived) {
      _arrived = true;
      _arrivalDialogShown = true;
    }
  }

  Future<void> _copyCode() async {
    final circle = _circle;
    if (circle == null) return;

    await Clipboard.setData(ClipboardData(text: circle.code));
    _showSnack('Circle code copied');
  }

  Future<void> _leaveOrEndCircle() async {
    final circle = _circle;
    if (circle == null || _isClosing) return;

    _closePageImmediately();

    if (circle.hostId == widget.me.id) {
      unawaited(_sessionService.endSession(circle.code));
    } else {
      unawaited(
        _sessionService.leaveSession(
          code: circle.code,
          uid: widget.me.id,
        ),
      );
    }
  }

  // Send SOS alert
  Future<void> _sendSos() async {
    final circle = _circle;
    if (circle == null || _isClosing) return;

    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Optional message',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _sessionService.sendSos(
      code: circle.code,
      sender: widget.me,
      message: controller.text.trim(),
      latitude: _myLatLng?.latitude,
      longitude: _myLatLng?.longitude,
    );

    _showSnack('SOS alert sent.');
  }

  // Send chat message
  Future<void> _sendChatMessage() async {
    final circle = _circle;

    if (circle == null || _isClosing) return;

    final text = _messageController.text.trim();

    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await _chatService.sendMessage(
        circleCode: circle.code,
        senderId: widget.me.id,
        senderName: widget.me.name,
        text: text,
      );
    } catch (e) {
      _messageController.text = text;
      _showSnack('Could not send message: $e');
    }
  }

  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Text(
                  _circle == null
                      ? 'Circle members'
                      : '${_circle!.name} members',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final member in _members)
                  ListTile(
                    leading: CircleAvatar(child: Text(member.initials)),
                    title: Text(member.name),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _meetupCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_2, color: Color(0xFF1E88E5)),
              SizedBox(width: 8),
              Text(
                'Meet Up Point',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_meetupPoint == null) ...[
            TextField(
              controller: _meetupController,
              enabled: !_isClosing,
              decoration: const InputDecoration(
                hintText: 'Enter meetup place',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isClosing ? null : _setMeetupPoint,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Share meetup point'),
              ),
            ),
          ] else ...[
            Text(
              _meetupPoint!.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Set by ${_meetupPoint!.createdByName}'),
            const SizedBox(height: 10),
            if (_loadingRoute)
              const LinearProgressIndicator()
            else if (_routeDistanceText != null && _routeDurationText != null)
              Text(
                'Distance: $_routeDistanceText • ETA: $_routeDurationText\n${_routeNote ?? ''}',
              )
            else
              const Text('Waiting for your location to calculate route.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isClosing
                        ? null
                        : () {
                            setState(() {
                              _focusedLocation = _meetupPoint!.latLng;
                            });
                          },
                    icon: const Icon(Icons.map),
                    label: const Text('Show on map'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isClosing ? null : _clearMeetupPoint,
                    icon: const Icon(Icons.close),
                    label: const Text('Remove'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatCard() {
    final circle = _circle;
    if (circle == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return _sectionCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Circle Chat',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 300,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.streamMessages(circle.code),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet. Say hello 👋',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final isMe = data['senderId'] == widget.me.id;
                    final senderName =
                        (data['senderName'] ?? 'Unknown').toString();
                    final text = (data['text'] ?? '').toString();

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.68,
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  senderName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            Text(
                              text,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              12 + MediaQuery.of(context).viewInsets.bottom * 0,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isClosing,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendChatMessage(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      prefixIcon: const Icon(Icons.message_outlined),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 50,
                  width: 50,
                  child: FilledButton(
                    onPressed: _isClosing ? null : _sendChatMessage,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(Icons.send_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Card(
      child: Padding(padding: padding, child: child),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final circle = _circle;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(circle?.name ?? 'Circle')),
      floatingActionButton: keyboardOpen || circle == null || _isClosing
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'sos_btn_detail',
                  onPressed: _sendSos,
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('SOS'),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'members_btn_detail',
                  onPressed: _showMembersSheet,
                  icon: const Icon(Icons.people),
                  label: const Text('Members'),
                ),
              ],
            ),
      body: circle == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  keyboardOpen ? 16 : 96,
                ),
                child: Column(
                  children: [
                    if (_locError != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _locError!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    _sectionCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(child: Icon(Icons.groups)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  circle.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              Text('${_members.length} members'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isClosing ? null : _copyCode,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy code'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed:
                                      _isClosing ? null : _leaveOrEndCircle,
                                  icon: const Icon(Icons.logout),
                                  label: Text(
                                    circle.hostId == widget.me.id
                                        ? 'End circle'
                                        : 'Leave circle',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _meetupCard(),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 420,
                      child: SessionMap(
                        locations: _locations,
                        currentUserId: widget.me.id,
                        myRealLocation: _myLatLng,
                        precisionMode: circle.precisionMode,
                        destination: circle.destination,
                        focusedLocation: _focusedLocation,
                        meetupPoint: _meetupPoint,
                        routePoints: _routePoints,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _chatCard(),
                  ],
                ),
              ),
            ),
    );
  }
}
