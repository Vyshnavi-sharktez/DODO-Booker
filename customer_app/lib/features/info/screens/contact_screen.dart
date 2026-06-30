import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactScreen extends StatelessWidget {
  final bool inModal;
  const ContactScreen({super.key, this.inModal = false});

  static const supportEmail = 'support@dodobooker.com';
  static const supportPhone = '+91 1800-123-4567';
  static const websiteUrl = 'https://www.dodobooker.com';

  @override
  Widget build(BuildContext context) {
    final body = const _ContactBody();
    if (inModal) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Us')),
      body: body,
    );
  }
}

class _ContactBody extends StatelessWidget {
  const _ContactBody();

  Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${uri.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get in Touch',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Our support team is here to help with bookings, account issues, and general enquiries.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface.withAlpha(180),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          _ContactTile(
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: ContactScreen.supportEmail,
            onTap: () => _launch(
              context,
              Uri(scheme: 'mailto', path: ContactScreen.supportEmail),
            ),
          ),
          const SizedBox(height: 12),
          _ContactTile(
            icon: Icons.phone_outlined,
            title: 'Phone',
            subtitle: ContactScreen.supportPhone,
            onTap: () => _launch(
              context,
              Uri(scheme: 'tel', path: ContactScreen.supportPhone),
            ),
          ),
          const SizedBox(height: 12),
          _ContactTile(
            icon: Icons.language_outlined,
            title: 'Website',
            subtitle: ContactScreen.websiteUrl,
            onTap: () => _launch(context, Uri.parse(ContactScreen.websiteUrl)),
          ),
          const SizedBox(height: 12),
          _ContactTile(
            icon: Icons.schedule_outlined,
            title: 'Support Hours',
            subtitle: 'Mon – Sat, 9:00 AM – 7:00 PM IST',
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withAlpha(80), width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withAlpha(160),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.open_in_new_rounded,
                    size: 18, color: cs.onSurface.withAlpha(120)),
            ],
          ),
        ),
      ),
    );
  }
}
