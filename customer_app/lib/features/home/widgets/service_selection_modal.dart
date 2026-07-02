import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../features/category/services/category_providers.dart';
import '../../../models/category_model.dart';
import '../../../models/service_model.dart';
import '../../../models/subcategory_model.dart';
import '../../../features/service/utils/service_detail_launcher.dart';

// ── Public entry point ────────────────────────────────────────────────────────

class ServiceSelectionModal {
  static Future<void> show(BuildContext context, CategoryModel category) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withAlpha(150),
      builder: (dialogContext) => _ServiceSelectionDialog(
        category: category,
        onServiceResolved: (service) {
          Navigator.of(dialogContext).pop();
          openServiceDetail(context, service);
        },
      ),
    );
  }
}

// ── Dialog ────────────────────────────────────────────────────────────────────

class _ServiceSelectionDialog extends ConsumerStatefulWidget {
  final CategoryModel category;
  final ValueChanged<ServiceModel> onServiceResolved;

  const _ServiceSelectionDialog({
    required this.category,
    required this.onServiceResolved,
  });

  @override
  ConsumerState<_ServiceSelectionDialog> createState() =>
      _ServiceSelectionDialogState();
}

class _ServiceSelectionDialogState
    extends ConsumerState<_ServiceSelectionDialog> {
  bool _loading = false;

  // When a subcategory tile is tapped, resolve its service and hand off.
  Future<void> _selectSubcategory(SubcategoryModel sub) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final details =
          await ref.read(subcategoryDetailsProvider(sub.id).future);
      if (!mounted) return;
      if (details.service != null) {
        widget.onServiceResolved(details.service!);
      }
    } catch (e) {
      debugPrint('[Modal] subcategoryDetailsProvider error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final isWide = screenW > 600;

    return Dialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: isWide
            ? BorderRadius.circular(24)
            : const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
      ),
      insetPadding: isWide
          ? const EdgeInsets.symmetric(horizontal: 48, vertical: 32)
          : EdgeInsets.only(top: screenH * 0.16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 680 : double.infinity,
          maxHeight: screenH * 0.84,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: widget.category.name,
                subtitle:
                    widget.category.description?.isNotEmpty == true
                        ? widget.category.description!
                        : 'Choose a service for your home',
                onClose: () => Navigator.of(context).pop(),
              ),
              if (_loading)
                const LinearProgressIndicator(minHeight: 2),
              Flexible(
                child: _SubcategoryStep(
                  categoryId: widget.category.id,
                  onSelect: _selectSubcategory,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outline.withAlpha(40))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: cs.onSurfaceVariant,
                padding: EdgeInsets.zero,
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subcategory vertical list ─────────────────────────────────────────────────

class _SubcategoryStep extends ConsumerWidget {
  final String categoryId;
  final ValueChanged<SubcategoryModel> onSelect;

  const _SubcategoryStep({required this.categoryId, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subcategoriesProvider(categoryId));

    return async.when(
      loading: () => const _Loader(),
      error: (e, _) {
        debugPrint('[Modal] subcategoriesProvider error: $e');
        return const _Empty(
            message: 'Could not load categories. Please try again.');
      },
      data: (subs) {
        if (subs.isEmpty) {
          return const _Empty(
              message: 'No services available in this category yet.');
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            children: [
              for (int i = 0; i < subs.length; i++) ...[
                _ServiceTile(
                  sub: subs[i],
                  onTap: () => onSelect(subs[i]),
                ),
                if (i < subs.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Premium service tile ───────────────────────────────────────────────────────

class _ServiceTile extends StatefulWidget {
  final SubcategoryModel sub;
  final VoidCallback onTap;

  const _ServiceTile({required this.sub, required this.onTap});

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final imgUrl = ServiceImageRegistry.resolve(
      widget.sub.imageUrl ?? widget.sub.iconUrl,
      widget.sub.name,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _pressed ? cs.surfaceContainerHighest : cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered ? AppColors.gold : cs.outline.withAlpha(80),
              width: _hovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? AppColors.gold.withAlpha(55)
                    : Colors.black.withAlpha(10),
                blurRadius: _hovered ? 22 : 6,
                spreadRadius: _hovered ? 1 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, p) =>
                        p == null
                            ? child
                            : const ColoredBox(color: Color(0xFFEEEEEE)),
                    errorBuilder: (context, error, stack) =>
                        _ThumbnailFallback(name: widget.sub.name),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.sub.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        height: 1.25,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (widget.sub.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.sub.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ] else if (widget.sub.serviceCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${widget.sub.serviceCount} '
                        '${widget.sub.serviceCount == 1 ? 'service' : 'services'} available',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withAlpha(120),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _hovered ? AppColors.gold : AppColors.goldLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: _hovered ? Colors.black : AppColors.gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Thumbnail fallback ────────────────────────────────────────────────────────

class _ThumbnailFallback extends StatelessWidget {
  final String name;
  const _ThumbnailFallback({required this.name});

  static const _gradients = <List<Color>>[
    [Color(0xFF1A1A2E), Color(0xFF16213E)],
    [Color(0xFF111111), Color(0xFF2C2C2C)],
    [Color(0xFF0D1117), Color(0xFF1C2833)],
    [Color(0xFF1B0A0A), Color(0xFF2D1515)],
    [Color(0xFF0A0F1C), Color(0xFF111827)],
  ];

  @override
  Widget build(BuildContext context) {
    final idx = name.hashCode.abs() % _gradients.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradients[idx],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.home_repair_service_rounded,
          size: 26,
          color: Colors.white.withAlpha(80),
        ),
      ),
    );
  }
}

// ── Shared utility widgets ────────────────────────────────────────────────────

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 160,
      child: Center(
        child: CircularProgressIndicator(
          color: cs.primary,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  final IconData icon;

  const _Empty({
    required this.message,
    this.icon = Icons.inbox_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 160,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: cs.onSurface.withAlpha(120)),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
