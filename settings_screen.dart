import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import 'change_password_screen.dart';

// App settings and account options
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follow phone setting';
      case ThemeMode.light:
        return 'Light mode';
      case ThemeMode.dark:
        return 'Dark mode';
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
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
      await FirebaseAuth.instance.signOut();

      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<AppPreferences>(
      valueListenable: settings,
      builder: (context, prefs, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings,
                          size: 42,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'App settings',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Manage your account and app preferences.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Account information'),
                        subtitle: Text(user?.email ?? 'No email found'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Change password'),
                        subtitle: const Text(
                          'Requires your old password first',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChangePasswordScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Log out'),
                        subtitle: const Text('Sign out of this account'),
                        onTap: () => _confirmLogout(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dark_mode_outlined),
                        title: const Text('Appearance'),
                        subtitle: Text(_themeLabel(prefs.themeMode)),
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Follow phone setting'),
                        value: ThemeMode.system,
                        groupValue: prefs.themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            settings.value = prefs.copyWith(themeMode: value);
                          }
                        },
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Light mode'),
                        value: ThemeMode.light,
                        groupValue: prefs.themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            settings.value = prefs.copyWith(themeMode: value);
                          }
                        },
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Dark mode'),
                        value: ThemeMode.dark,
                        groupValue: prefs.themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            settings.value = prefs.copyWith(themeMode: value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.text_fields),
                            SizedBox(width: 10),
                            Text(
                              'Text size',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Current size: ${(prefs.textScale * 100).round()}%',
                        ),
                        Slider(
                          min: 0.85,
                          max: 1.35,
                          divisions: 5,
                          value: prefs.textScale,
                          label: '${(prefs.textScale * 100).round()}%',
                          onChanged: (value) {
                            settings.value = prefs.copyWith(textScale: value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: const [
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined),
                        title: Text('Privacy-first sharing'),
                        subtitle: Text(
                          'Only share location inside trusted circles.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.timer_outlined),
                        title: Text('Auto-ending circles'),
                        subtitle: Text(
                          'Use auto-end to avoid sharing longer than needed.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.chat_bubble_outline),
                        title: Text('Circle chat'),
                        subtitle: Text(
                          'Message members directly inside each circle.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
