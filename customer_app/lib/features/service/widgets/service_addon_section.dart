import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/addon_model.dart';

/// Horizontally scrollable "Suggested Add-ons" section.
///
/// - Parent tracks selection state and fires [onToggle] on each tap.
/// - A right-edge fade gradient gives clear scroll affordance.
/// - The header counts selected add-ons when at least one is chosen.
/// - Cards animate between selected / unselected states.
class ServiceAddonSection extends StatelessWidget {
  final List<AddOnModel> addOns;
  final Set<String> selectedIds;
  final void Function(String addonId, bool selected) onToggle;

  const ServiceAddonSection({
    super.key,
    required this.addOns,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (addOns.isEmpty) return const SizedBox.shrink();

    final selectedCount =
        addOns.where((a) => selectedIds.contains(a.id)).length;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Suggested Add-ons',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              _OptionalBadge(),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selectedCount > 0
                    ? _SelectedCountBadge(
                        key: ValueKey(selectedCount),
                        count: selectedCount,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        // ── Hint text ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 5, 20, 14),
          child: Text(
            addOns.length > 2
                ? 'Scroll to see all ${addOns.length} options'
                : 'Optional extras to enhance your service',
            style: tt.bodySmall?.copyWith(color: AppColors.textHint),
          ),
        ),

        // ── Scrollable list with fade edge ─────────────────────────────────
        SizedBox(
          height: _AddonCard.cardHeight,
          child: Stack(
            children: [
              ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: addOns.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _AddonCard(
                  addOn: addOns[i],
                  isSelected: selectedIds.contains(addOns[i].id),
                  onToggle: (sel) => onToggle(addOns[i].id, sel),
                ),
              ),

              // Right-edge fade — hints there's more to scroll
              if (addOns.length > 2)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 48,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppColors.background.withAlpha(0),
                            AppColors.background,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── "Optional" pill badge ─────────────────────────────────────────────────────

class _OptionalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold.withAlpha(24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Optional',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.gold,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ── Selected count badge ──────────────────────────────────────────────────────

class _SelectedCountBadge extends StatelessWidget {
  final int count;
  const _SelectedCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$count selected',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual add-on card ────────────────────────────────────────────────────

class _AddonCard extends StatelessWidget {
  static const double cardWidth = 172.0;
  static const double cardHeight = 130.0;

  final AddOnModel addOn;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  const _AddonCard({
    required this.addOn,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasDesc =
        addOn.description != null && addOn.description!.isNotEmpty;

    return GestureDetector(
      onTap: () => onToggle(!isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.goldLight : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.gold.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name row + checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    addOn.name,
                    style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: hasDesc ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _Checkbox(isSelected: isSelected),
              ],
            ),

            // Description (optional)
            if (hasDesc) ...[
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  addOn.description!,
                  style: tt.bodySmall?.copyWith(
                    color: isSelected
                        ? AppColors.textSecondary
                        : AppColors.textHint,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              const Spacer(),

            // Price
            const SizedBox(height: 6),
            Text(
              '+ ₹${addOn.price.toInt()}',
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isSelected ? AppColors.gold : AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated checkbox ─────────────────────────────────────────────────────────

class _Checkbox extends StatelessWidget {
  final bool isSelected;
  const _Checkbox({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.gold : Colors.transparent,
        border: Border.all(
          color: isSelected ? AppColors.gold : AppColors.border,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : const Icon(Icons.add_rounded, size: 13, color: AppColors.textHint),
    );
  }
}
