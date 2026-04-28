import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/live_location.dart';
import '../models/meetup_point.dart';
import '../models/place.dart';
import '../models/session.dart';

// Map showing users, destination, and meetup point
class SessionMap extends StatefulWidget {
  final List<LiveLocation> locations;
  final String currentUserId;
  final LatLng? myRealLocation;
  final PrecisionMode precisionMode;
  final Place? destination;
  final LatLng? focusedLocation;
  final MeetupPoint? meetupPoint;
  final List<LatLng> routePoints;

  const SessionMap({
    super.key,
    required this.locations,
    required this.currentUserId,
    required this.myRealLocation,
    required this.precisionMode,
    required this.destination,
    required this.focusedLocation,
    required this.meetupPoint,
    required this.routePoints,
  });

  @override
  State<SessionMap> createState() => _SessionMapState();
}

class _SessionMapState extends State<SessionMap> {
  static const _green = Color(0xFF19A15F);
  static const _darkGreen = Color(0xFF0B6B3A);
  static const _blue = Color(0xFF1E88E5);

  final MapController _controller = MapController();

  double _zoom = 14;
  LatLng? _lastFocusedLocation;

  double _blurRadius(PrecisionMode mode) {
    switch (mode) {
      case PrecisionMode.exact:
        return 0;
      case PrecisionMode.street:
        return 50;
      case PrecisionMode.area:
        return 250;
      case PrecisionMode.city:
        return 1000;
    }
  }

  LiveLocation? _myUploadedLocation() {
    for (final loc in widget.locations) {
      if (loc.uid == widget.currentUserId) {
        return loc;
      }
    }
    return null;
  }

  List<LiveLocation> _otherLocations() {
    return widget.locations
        .where((loc) => loc.uid != widget.currentUserId)
        .toList();
  }

  @override
  void didUpdateWidget(covariant SessionMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final focus = widget.focusedLocation;

    if (focus != null && focus != _lastFocusedLocation) {
      _lastFocusedLocation = focus;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.move(focus, 16);
      });
    }
  }

  void _zoomIn() {
    _zoom = (_zoom + 1).clamp(3, 19).toDouble();
    _controller.move(_controller.camera.center, _zoom);
    setState(() {});
  }

  void _zoomOut() {
    _zoom = (_zoom - 1).clamp(3, 19).toDouble();
    _controller.move(_controller.camera.center, _zoom);
    setState(() {});
  }

  void _centerOnMe(LatLng me) {
    _controller.move(me, 16);
  }

  Widget _pin({
    required Color color,
    required String label,
    IconData? icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 3),
            color: Colors.black26,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: icon == null
          ? Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            )
          : Icon(icon, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    const fallback = LatLng(52.4862, -1.8904);

    final myUploaded = _myUploadedLocation();
    final others = _otherLocations();

    final meDisplayed = widget.myRealLocation ?? myUploaded?.latLng ?? fallback;

    final blurMeters = _blurRadius(widget.precisionMode);

    final markers = <Marker>[
      Marker(
        point: meDisplayed,
        width: 48,
        height: 48,
        child: _pin(
          color: _darkGreen,
          label: myUploaded?.initials.isNotEmpty == true
              ? myUploaded!.initials
              : 'Y',
        ),
      ),
    ];

    for (final loc in others) {
      markers.add(
        Marker(
          point: loc.latLng,
          width: 48,
          height: 48,
          child: _pin(
            color: _green,
            label: loc.initials,
          ),
        ),
      );
    }

    if (widget.destination != null) {
      markers.add(
        Marker(
          point: widget.destination!.latLng,
          width: 52,
          height: 52,
          child: _pin(
            color: Colors.orange,
            label: '',
            icon: Icons.flag,
          ),
        ),
      );
    }

    if (widget.meetupPoint != null) {
      markers.add(
        Marker(
          point: widget.meetupPoint!.latLng,
          width: 56,
          height: 56,
          child: _pin(
            color: _blue,
            label: '',
            icon: Icons.groups_2,
          ),
        ),
      );
    }

    final circles = <CircleMarker>[];

    if (blurMeters > 0) {
      circles.add(
        CircleMarker(
          point: meDisplayed,
          radius: blurMeters,
          useRadiusInMeter: true,
          color: _green.withOpacity(0.10),
          borderColor: _green.withOpacity(0.35),
          borderStrokeWidth: 2,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: meDisplayed,
              initialZoom: _zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (pos, _) {
                _zoom = pos.zoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_application_1',
              ),
              if (circles.isNotEmpty) CircleLayer(circles: circles),
              if (widget.routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.routePoints,
                      strokeWidth: 5,
                      color: _blue,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(
                    label: 'You',
                    initials: myUploaded?.initials.isNotEmpty == true
                        ? myUploaded!.initials
                        : 'Y',
                    color: _darkGreen,
                    onTap: () => _controller.move(meDisplayed, 16),
                  ),
                  const SizedBox(width: 8),
                  for (final loc in others) ...[
                    _chip(
                      label: loc.name,
                      initials: loc.initials,
                      onTap: () => _controller.move(loc.latLng, 16),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (widget.meetupPoint != null) ...[
                    _chip(
                      label: 'Meet Up',
                      initials: 'M',
                      color: _blue,
                      onTap: () => _controller.move(
                        widget.meetupPoint!.latLng,
                        16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in_btn',
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'zoom_out_btn',
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'center_me_btn',
                  backgroundColor: _darkGreen,
                  foregroundColor: Colors.white,
                  onPressed: () => _centerOnMe(meDisplayed),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required String initials,
    required VoidCallback onTap,
    Color color = _green,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
