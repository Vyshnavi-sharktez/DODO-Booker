import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../features/category/services/category_providers.dart';
import '../../../models/category_model.dart';
import '../../../models/service_attribute_model.dart';
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

// ── Step enum ─────────────────────────────────────────────────────────────────

enum _Step { subcategory, attributes }

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
  _Step _step = _Step.subcategory;
  SubcategoryModel? _subcategory;
  int _animKey = 0;
  final Map<String, String> _selections = {}; // attributeId → optionId

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _selectSubcategory(SubcategoryModel sub) {
    setState(() {
      _animKey++;
      _subcategory = sub;
      _selections.clear();
      _step = _Step.attributes;
    });
  }

  void _goBack() {
    if (_step == _Step.subcategory) return;
    setState(() {
      _animKey++;
      _step = _Step.subcategory;
      _subcategory = null;
      _selections.clear();
    });
  }

  // ── Header labels ───────────────────────────────────────────────────────────

  String get _title =>
      _step == _Step.subcategory ? widget.category.name : _subcategory!.name;

  String get _subtitle => _step == _Step.subcategory
      ? (widget.category.description?.isNotEmpty == true
          ? widget.category.description!
          : 'Choose a service for your home')
      : 'Configure service details';

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
                title: _title,
                subtitle: _subtitle,
                breadcrumb: _step == _Step.attributes
                    ? '${widget.category.name}  ›  ${_subcategory!.name}'
                    : null,
                canGoBack: _step != _Step.subcategory,
                onBack: _goBack,
                onClose: () => Navigator.of(context).pop(),
              ),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) {
                    final curve =
                        CurvedAnimation(parent: anim, curve: Curves.easeOut);
                    return FadeTransition(
                      opacity: curve,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(curve),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_animKey),
                    child: _step == _Step.subcategory
                        ? _SubcategoryStep(
                            categoryId: widget.category.id,
                            onSelect: _selectSubcategory,
                          )
                        : _AttributeStep(
                            subcategoryId: _subcategory!.id,
                            selections: Map.unmodifiable(_selections),
                            onChanged: (attrId, optId) {
                              setState(() => _selections[attrId] = optId);
                            },
                          ),
                  ),
                ),
              ),
              if (_step == _Step.attributes)
                _Footer(
                  subcategoryId: _subcategory!.id,
                  selections: _selections,
                  onBook: widget.onServiceResolved,
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
  final String? breadcrumb;
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.breadcrumb,
    required this.canGoBack,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outline.withAlpha(40))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedOpacity(
                  opacity: canGoBack ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  child: IconButton(
                    onPressed: canGoBack ? onBack : null,
                    icon: const Icon(
                        Icons.arrow_back_ios_new_rounded, size: 17),
                    color: cs.onSurface,
                    splashRadius: 20,
                    tooltip: 'Back',
                  ),
                ),
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
          if (breadcrumb != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    breadcrumb!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.gold,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ── Step 1: Subcategory vertical list ─────────────────────────────────────────

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

// ── Premium service tile (replaces icon grid card) ────────────────────────────

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
              // ── Service thumbnail ──────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, p) =>
                        p == null ? child : const ColoredBox(color: Color(0xFFEEEEEE)),
                    errorBuilder: (context, error, stack) =>
                        _ThumbnailFallback(name: widget.sub.name),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // ── Name + description ─────────────────────────────────────
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

              // ── Arrow indicator ────────────────────────────────────────
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

// ── Thumbnail fallback for offline / missing images ───────────────────────────

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

// ── Step 2: Attribute selection ───────────────────────────────────────────────

class _AttributeStep extends ConsumerWidget {
  final String subcategoryId;
  final Map<String, String> selections;
  final void Function(String attrId, String optId) onChanged;

  const _AttributeStep({
    required this.subcategoryId,
    required this.selections,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subcategoryDetailsProvider(subcategoryId));

    return async.when(
      loading: () => const _Loader(),
      error: (e, _) {
        debugPrint('[Modal] subcategoryDetailsProvider error: $e');
        return const _Empty(message: 'Could not load service details. Please try again.');
      },
      data: (details) {
        if (!details.hasService) {
          return const _Empty(
            message: 'This service is coming soon. Check back shortly.',
            icon: Icons.schedule_rounded,
          );
        }

        if (!details.hasAttributes) {
          return const _Empty(
            message: 'No additional configuration needed — tap Continue to book.',
            icon: Icons.check_circle_outline_rounded,
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final attr in details.attributes)
                if (attr.hasOptions) ...[
                  _AttrSection(
                    attr: attr,
                    selectedId: selections[attr.id],
                    onSelect: (optId) => onChanged(attr.id, optId),
                  ),
                  const SizedBox(height: 20),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _AttrSection extends StatelessWidget {
  final ServiceAttributeModel attr;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _AttrSection({
    required this.attr,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              attr.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                letterSpacing: 0.1,
              ),
            ),
            if (attr.isRequired) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: attr.options
              .map((opt) => _Chip(
                    label: opt.optionName,
                    selected: selectedId == opt.id,
                    onTap: () => onSelect(opt.id),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: sel
                ? AppColors.primary
                : _hovered
                    ? AppColors.primaryLight
                    : cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel
                  ? AppColors.primary
                  : _hovered
                      ? AppColors.primary.withAlpha(80)
                      : cs.outline.withAlpha(80),
              width: sel ? 1.5 : 1.0,
            ),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(30),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: sel ? Colors.white : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends ConsumerWidget {
  final String subcategoryId;
  final Map<String, String> selections;
  final ValueChanged<ServiceModel> onBook;

  const _Footer({
    required this.subcategoryId,
    required this.selections,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(subcategoryDetailsProvider(subcategoryId));
    final details = detailsAsync.valueOrNull;

    final requiredIds = details?.attributes
            .where((a) => a.isRequired && a.hasOptions)
            .map((a) => a.id)
            .toSet() ??
        {};

    final allMet =
        requiredIds.isEmpty || requiredIds.every(selections.containsKey);
    final service = details?.service;
    final enabled = allMet && service != null;

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outline.withAlpha(60))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: ElevatedButton(
            onPressed: enabled ? () => onBook(service) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary,
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Continue to Booking',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
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
