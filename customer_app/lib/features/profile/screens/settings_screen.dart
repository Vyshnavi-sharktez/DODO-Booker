import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../routes/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import 'appearance_screen.dart';
import 'about_screen.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends ConsumerWidget {
  final bool inModal;
  const SettingsScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // ── APPEARANCE ─────────────────────────────────────────────
              _SectionLabel('Appearance'),

              _FloatingCard(
                child: _SettingsTile(
                  icon: Icons.palette_outlined,
                  iconColor: const Color(0xFF5C6BC0),
                  title: 'Appearance',
                  subtitle: 'Light or dark theme',
                  onTap: () => _open(
                    context,
                    title: 'Appearance',
                    modal: const AppearanceScreen(inModal: true),
                    screen: const AppearanceScreen(),
                  ),
                ),
              ),

              // ── ABOUT ──────────────────────────────────────────────────
              _SectionLabel('About'),

              _FloatingCard(
                child: _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: const Color(0xFF34A853),
                  title: 'About DODO Booker',
                  subtitle: 'Version, description and more',
                  onTap: () => _open(
                    context,
                    title: 'About DODO Booker',
                    modal: const AboutScreen(inModal: true),
                    screen: const AboutScreen(),
                  ),
                ),
              ),

              // ── LEGAL ──────────────────────────────────────────────────
              _SectionLabel('Legal'),

              _FloatingCard(
                child: _SettingsTile(
                  icon: Icons.shield_outlined,
                  iconColor: const Color(0xFF1A73E8),
                  title: 'Privacy Policy',
                  subtitle: 'How we handle your data',
                  onTap: () => _open(
                    context,
                    title: 'Privacy Policy',
                    modal: const PrivacyPolicyScreen(inModal: true),
                    screen: const PrivacyPolicyScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _FloatingCard(
                child: _SettingsTile(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFFFFA000),
                  title: 'Terms & Conditions',
                  subtitle: 'Our terms of service',
                  onTap: () => _open(
                    context,
                    title: 'Terms & Conditions',
                    modal: const TermsScreen(inModal: true),
                    screen: const TermsScreen(),
                  ),
                ),
              ),

              // ── LOGOUT ─────────────────────────────────────────────────
              const SizedBox(height: 32),
              _LogoutCard(),
              const SizedBox(height: 24),

              Center(
                child: Text(
                  'DODO Booker v1.0.0',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurface.withAlpha(80),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (inModal) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: body,
    );
  }

  static void _open(
    BuildContext context, {
    required String title,
    required Widget modal,
    required Widget screen,
  }) {
    if (MediaQuery.of(context).size.width >= 768) {
      PageSheet.show(context, title: title, child: modal);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }
  }
}

// ── Settings tile (fully theme-aware) ─────────────────────────────────────────

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final effectiveIconColor =
        widget.isDestructive ? cs.error : widget.iconColor;
    final titleColor =
        widget.isDestructive ? cs.error : cs.onSurface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _hovered
              ? (widget.isDestructive
                  ? cs.error.withAlpha(10)
                  : cs.onSurface.withAlpha(6))
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: effectiveIconColor.withAlpha(18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(widget.icon, size: 20, color: effectiveIconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        fontSize: 14,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle!,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!widget.isDestructive)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: _hovered
                      ? cs.onSurface.withAlpha(160)
                      : cs.onSurface.withAlpha(80),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Floating card wrapper ──────────────────────────────────────────────────────

class _FloatingCard extends StatelessWidget {
  final Widget child;
  const _FloatingCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withAlpha(100),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

// ── Logout card ────────────────────────────────────────────────────────────────

class _LogoutCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LogoutCard> createState() => _LogoutCardState();
}

class _LogoutCardState extends ConsumerState<_LogoutCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _SettingsTile(
          icon: Icons.logout_rounded,
          iconColor: cs.error,
          title: 'Logout',
          isDestructive: true,
          onTap: _loading ? null : () => _confirmLogout(context),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout?'),
        content: const Text(
          'Are you sure you want to logout of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              setState(() => _loading = true);
              final router = GoRouter.of(context);
              await ref.read(authServiceProvider).signOut();
              ref.read(authNotifierProvider.notifier).setAuthenticated(false);
              if (!mounted) return;
              setState(() => _loading = false);
              router.go(AppRoutes.home);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
