import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  final bool inModal;
  const AboutScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context) {
    final body = _AboutBody();
    if (inModal) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('About DODO Booker')),
      body: body,
    );
  }
}

class _AboutBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(24),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: cs.primaryContainer,
                  child: Icon(
                    Icons.home_repair_service_rounded,
                    size: 44,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ── App name ────────────────────────────────────────────────────
          Text(
            'DODO Booker',
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 4),

          Text(
            'Version 1.0.0  •  Build 1',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withAlpha(120)),
          ),

          const SizedBox(height: 32),

          // ── Description card ────────────────────────────────────────────
          _InfoCard(
            child: Text(
              'DODO Booker is a premium home services marketplace that connects you with verified, trusted professionals for all your home service needs — from repairs and cleaning to beauty and wellness.',
              style: tt.bodyMedium?.copyWith(
                height: 1.65,
                color: cs.onSurface.withAlpha(200),
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 16),

          // ── Feature highlights ───────────────────────────────────────────
          _InfoCard(
            child: Column(
              children: [
                _HighlightRow(
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF34A853),
                  text: 'Verified Professionals',
                ),
                Divider(height: 20, color: cs.outline.withAlpha(60)),
                _HighlightRow(
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF5C6BC0),
                  text: 'Transparent Pricing',
                ),
                Divider(height: 20, color: cs.outline.withAlpha(60)),
                _HighlightRow(
                  icon: Icons.lock_outline_rounded,
                  color: const Color(0xFFD4AF37),
                  text: 'Secure Booking',
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Copyright ────────────────────────────────────────────────────
          Text(
            '© 2025 DODO Booker. All rights reserved.',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withAlpha(100),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(80), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _HighlightRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: tt.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
