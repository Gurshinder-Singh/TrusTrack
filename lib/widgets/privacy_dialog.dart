import 'package:flutter/material.dart';

// Privacy and safety information dialog
class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  Widget _item(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFEAF5EE),
            child: Icon(icon, color: const Color(0xFF0B6B3A), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Privacy & Safety'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(
              Icons.lock_outline,
              'Session-based sharing',
              'Location is shared only while you are in active circles.',
            ),
            _item(
              Icons.tune,
              'Privacy precision',
              'You can reduce how accurately others see your location.',
            ),
            _item(
              Icons.flag_outlined,
              'Destination mode',
              'A circle can guide sharing until arrival.',
            ),
            _item(
              Icons.stop_circle_outlined,
              'Leave any time',
              'You can leave a circle or end one you host.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
