import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/theme_provider.dart';

class AppearanceScreen extends ConsumerWidget {
  final bool inModal;
  const AppearanceScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THEME',
            style: tt.labelSmall?.copyWith(
              color: cs.onSurface.withAlpha(100),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _ThemeOptionCard(
            icon: Icons.wb_sunny_rounded,
            label: 'Light',
            subtitle: 'Bright and clean interface',
            selected: themeMode == ThemeMode.light,
            onTap: () => ref.read(themeProvider.notifier).setTheme(ThemeMode.light),
          ),
          const SizedBox(height: 12),
          _ThemeOptionCard(
            icon: Icons.dark_mode_rounded,
            label: 'Dark',
            subtitle: 'Easy on the eyes',
            selected: themeMode == ThemeMode.dark,
            onTap: () => ref.read(themeProvider.notifier).setTheme(ThemeMode.dark),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.primary.withAlpha(30),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Theme changes apply instantly across the entire app.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.primary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (inModal) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: body,
    );
  }
}

// ── Theme option card ──────────────────────────────────────────────────────────

class _ThemeOptionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ThemeOptionCard> createState() => _ThemeOptionCardState();
}

class _ThemeOptionCardState extends State<_ThemeOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected
                  ? cs.primary
                  : cs.outline.withAlpha(100),
              width: widget.selected ? 2.0 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 20 : 10),
                blurRadius: _hovered ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? cs.primary.withAlpha(20)
                      : cs.onSurface.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 22,
                  color: widget.selected
                      ? cs.primary
                      : cs.onSurface.withAlpha(140),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: tt.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: widget.selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey(true),
                        color: cs.primary,
                        size: 22,
                      )
                    : Icon(
                        Icons.circle_outlined,
                        key: const ValueKey(false),
                        color: cs.outline.withAlpha(100),
                        size: 22,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
