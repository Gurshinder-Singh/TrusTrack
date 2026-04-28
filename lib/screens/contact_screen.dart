import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Contact and support screen
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  Future<void> _emailOwner(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'owner@trusttrack.app',
      query: 'subject=TrusTrack Support Request',
    );

    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact TrusTrack'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.support_agent,
                      size: 44,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Need help?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use this page to contact the app owner if you need help, want to report a problem, or have feedback about TrusTrack.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _emailOwner(context),
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('Email app owner'),
                      ),
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
                    leading: Icon(Icons.person_outline),
                    title: Text('App owner'),
                    subtitle: Text('TrusTrack Support Team'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.alternate_email),
                    title: Text('Email'),
                    subtitle: Text('owner@trusttrack.app'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('App purpose'),
                    subtitle: Text(
                      'Consent-based live location sharing for trusted circles.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
