import 'dart:async';

import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/location_sync_service.dart';
import '../services/session_service.dart';
import '../widgets/privacy_dialog.dart';
import 'circle_details_screen.dart';
import 'contact_screen.dart';
import 'settings_screen.dart';

// Main dashboard for managing circles
class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final _auth = AuthService();
  final _sessionService = SessionService();
  final _locationSyncService = LocationSyncService();

  final _joinController = TextEditingController();
  final _circleNameController = TextEditingController();

  Person? _me;
  List<ShareSession> _myCircles = [];

  StreamSubscription? _myCirclesSub;
  Timer? _autoEndTimer;

  bool _loadingUser = true;
  bool _refreshing = false;
  bool _creating = false;
  bool _joining = false;

  PrecisionMode _precision = PrecisionMode.exact;
  int _autoEndMinutes = 0;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _joinController.dispose();
    _circleNameController.dispose();
    _myCirclesSub?.cancel();
    _autoEndTimer?.cancel();
    _locationSyncService.stop();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _auth.getCurrentPerson();

      if (!mounted) return;

      setState(() {
        _me = user;
        _loadingUser = false;
      });

      _watchMyCircles();
      _startAutoEndChecker();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUser = false);
      _showSnack(e.toString());
    }
  }

  // Listen to user's active circles
  void _watchMyCircles() {
    final me = _me;
    if (me == null) return;

    _myCirclesSub?.cancel();

    _myCirclesSub = _sessionService.streamUserCircles(me.id).listen((circles) {
      if (!mounted) return;

      setState(() => _myCircles = circles);

      final codes = circles.map((e) => e.code).toList();

      if (codes.isNotEmpty) {
        unawaited(_startLocationSyncSafely(codes));
      } else {
        _locationSyncService.stop();
      }
    });
  }

  void _startAutoEndChecker() {
    _autoEndTimer?.cancel();

    _autoEndTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final me = _me;
      if (me == null) return;

      await _sessionService.cleanupExpiredUserCircles(me.id);
      await _refreshCirclesOnce(showLoading: false);
    });
  }

  Future<void> _startLocationSyncSafely(List<String> codes) async {
    final me = _me;
    if (me == null || codes.isEmpty) return;

    try {
      _locationSyncService.setUser(me);

      await _locationSyncService.startForUser(
        me: me,
        sessionCodes: codes,
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _uploadLocationToCircleSafely(String code) async {
    final me = _me;
    if (me == null) return;

    try {
      _locationSyncService.setUser(me);

      await _locationSyncService.uploadCurrentLocationToCircle(
        code: code,
        me: me,
      );
    } catch (_) {}
  }

  Future<void> _refreshCirclesOnce({bool showLoading = true}) async {
    final me = _me;
    if (me == null) return;

    if (showLoading && mounted) {
      setState(() => _refreshing = true);
    }

    try {
      await _sessionService.cleanupExpiredUserCircles(me.id);

      final circles = await _sessionService.streamUserCircles(me.id).first;

      if (!mounted) return;

      setState(() => _myCircles = circles);

      final codes = circles.map((e) => e.code).toList();

      if (codes.isNotEmpty) {
        unawaited(_startLocationSyncSafely(codes));
      } else {
        _locationSyncService.stop();
      }
    } finally {
      if (mounted && showLoading) {
        setState(() => _refreshing = false);
      }
    }
  }

  DateTime? _buildEndTime() {
    if (_autoEndMinutes <= 0) return null;
    return DateTime.now().add(Duration(minutes: _autoEndMinutes));
  }

  // Create a new circle
  Future<void> _createCircle() async {
    final me = _me;

    if (me == null || _creating) return;

    final circleName = _circleNameController.text.trim();

    if (circleName.isEmpty) {
      _showSnack('Enter a circle name.');
      return;
    }

    final createdAt = DateTime.now();
    final endsAt = _buildEndTime();

    setState(() => _creating = true);

    try {
      final code = await _sessionService.createSession(
        host: me,
        circleName: circleName,
        precisionMode: _precision,
        purpose: SharePurpose.general,
        destination: null,
        endsAt: endsAt,
      );

      final created = ShareSession(
        code: code,
        name: circleName,
        hostId: me.id,
        hostName: me.name,
        createdAt: createdAt,
        endsAt: endsAt,
        precisionMode: _precision,
        purpose: SharePurpose.general,
        destination: null,
        isActive: true,
      );

      _circleNameController.clear();

      if (!mounted) return;

      setState(() {
        _creating = false;
        _myCircles = [
          created,
          ..._myCircles.where((c) => c.code != created.code),
        ];
      });

      unawaited(_startLocationSyncSafely([
        ..._myCircles.map((e) => e.code),
        created.code,
      ]));

      unawaited(_uploadLocationToCircleSafely(created.code));

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CircleDetailsScreen(
            me: me,
            initialCircle: created,
          ),
        ),
      );

      await _refreshCirclesOnce(showLoading: false);
    } catch (e) {
      _showSnack('Could not create circle: $e');
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  // Join an existing circle
  Future<void> _joinCircle() async {
    final me = _me;

    if (me == null || _joining) return;

    final code = _joinController.text.trim().toUpperCase();

    if (code.isEmpty) {
      _showSnack('Enter a circle code.');
      return;
    }

    setState(() => _joining = true);

    try {
      final ok = await _sessionService.joinSession(
        code: code,
        person: me,
      );

      if (!ok) {
        _showSnack('Circle not found, inactive, or expired.');
        return;
      }

      _joinController.clear();

      final joined = await _sessionService.getSessionByCode(code);

      if (joined == null) {
        _showSnack('Joined circle, but could not load it.');
        return;
      }

      if (!mounted) return;

      setState(() {
        _joining = false;
        _myCircles = [
          joined,
          ..._myCircles.where((c) => c.code != joined.code),
        ];
      });

      unawaited(_startLocationSyncSafely([
        ..._myCircles.map((e) => e.code),
        joined.code,
      ]));

      unawaited(_uploadLocationToCircleSafely(joined.code));

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CircleDetailsScreen(
            me: me,
            initialCircle: joined,
          ),
        ),
      );

      await _refreshCirclesOnce(showLoading: false);
    } catch (e) {
      _showSnack('Could not join circle: $e');
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  Future<void> _openCircle(ShareSession circle) async {
    final me = _me;
    if (me == null) return;

    unawaited(_uploadLocationToCircleSafely(circle.code));

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CircleDetailsScreen(
          me: me,
          initialCircle: circle,
        ),
      ),
    );

    await _refreshCirclesOnce(showLoading: false);
  }

  void _showActiveCirclesSheet() {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Icon(
                          Icons.groups,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Active circles',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_myCircles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        'No active circles yet.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _myCircles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final circle = _myCircles[index];

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(
                                Icons.location_on,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              circle.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${circle.code} • ${_endsAtText(circle.endsAt)} • ${_precisionText(circle.precisionMode)}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              final selected = circle;
                              Navigator.of(sheetContext).pop();

                              Future.delayed(
                                const Duration(milliseconds: 120),
                                () {
                                  if (mounted) _openCircle(selected);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out of TrusTrack?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _auth.signOut();
    }
  }

  String _endsAtText(DateTime? endsAt) {
    if (endsAt == null) return 'No auto-end';

    final diff = endsAt.difference(DateTime.now());

    if (diff.isNegative) return 'Expired';

    if (diff.inHours >= 1) {
      return 'Ends in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }

    if (diff.inMinutes >= 1) {
      return 'Ends in ${diff.inMinutes}m';
    }

    return 'Ending soon';
  }

  String _precisionText(PrecisionMode mode) {
    switch (mode) {
      case PrecisionMode.exact:
        return 'Exact';
      case PrecisionMode.street:
        return 'Street';
      case PrecisionMode.area:
        return 'Area';
      case PrecisionMode.city:
        return 'City';
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 17,
            color: cs.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TrusTrack'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Privacy',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const PrivacyDialog(),
            ),
            icon: const Icon(Icons.shield_outlined),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loadingUser || me == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refreshCirclesOnce(),
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_refreshing)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(),
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 31,
                                backgroundColor: cs.primaryContainer,
                                child: Icon(
                                  Icons.location_on_rounded,
                                  size: 34,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome, ${me.name}',
                                      style: const TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Stay connected safely with your trusted circles.',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(
                              'Active circles',
                              subtitle:
                                  'View and switch between your live circles.',
                            ),
                            const SizedBox(height: 14),
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _showActiveCirclesSheet,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: cs.primary,
                                      child: Text(
                                        _myCircles.length.toString(),
                                        style: TextStyle(
                                          color: cs.onPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _myCircles.isEmpty
                                            ? 'No active circles'
                                            : '${_myCircles.length} active circle(s)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.expand_more_rounded),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(
                              'Join circle',
                              subtitle: 'Enter a code shared by another user.',
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _joinController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'Enter circle code',
                                prefixIcon: Icon(Icons.key_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _joining ? null : _joinCircle,
                                icon: _joining
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.group_add),
                                label: Text(
                                  _joining ? 'Joining...' : 'Join circle',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(
                              'Create circle',
                              subtitle:
                                  'Start a private live location session.',
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _circleNameController,
                              decoration: const InputDecoration(
                                hintText: 'Circle name',
                                prefixIcon: Icon(Icons.groups),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<PrecisionMode>(
                              initialValue: _precision,
                              decoration: const InputDecoration(
                                labelText: 'Privacy precision',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: PrecisionMode.exact,
                                  child: Text('Exact location'),
                                ),
                                DropdownMenuItem(
                                  value: PrecisionMode.street,
                                  child: Text('Street level'),
                                ),
                                DropdownMenuItem(
                                  value: PrecisionMode.area,
                                  child: Text('Area level'),
                                ),
                                DropdownMenuItem(
                                  value: PrecisionMode.city,
                                  child: Text('City level'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _precision = v);
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _autoEndMinutes,
                              decoration: const InputDecoration(
                                labelText: 'Circle auto-end',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('No auto-end'),
                                ),
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('End after 1 minute'),
                                ),
                                DropdownMenuItem(
                                  value: 5,
                                  child: Text('End after 5 minutes'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('End after 30 minutes'),
                                ),
                                DropdownMenuItem(
                                  value: 60,
                                  child: Text('End after 1 hour'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _autoEndMinutes = v);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                ),
                                onPressed: _creating ? null : _createCircle,
                                icon: _creating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add_circle_outline),
                                label: Text(
                                  _creating ? 'Creating...' : 'Create circle',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ContactScreen(),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: cs.surfaceContainerHighest,
                            border: Border.all(
                              color: cs.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: cs.primaryContainer,
                                child: Icon(
                                  Icons.support_agent,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Need help?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Contact TrusTrack support',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
