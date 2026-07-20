import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/preferred_vendor_provider.dart';

/// Horizontally scrollable "Preferred Vendors" section.
///
/// Each vendor card shows a simple AVAILABLE / VENDOR CURRENTLY BUSY badge
/// derived from live booking status via [vendorBusyProvider].  Busy vendors
/// are disabled — customers cannot select them.  Selection clears
/// automatically when the vendor's active job reaches Completed, Cancelled,
/// or Rejected (next time the section enters the widget tree).
///
/// Returns [SizedBox.shrink] while loading, on error, or when no vendors are
/// configured / enabled for the given service.
class PreferredVendorSection extends ConsumerWidget {
  final String serviceId;
  final String? parentNodeId;
  final double? lat;
  final double? lng;
  final DateTime? selectedDate;
  final String? selectedVendorId;
  final void Function(String? id, String? name, double fee) onSelect;
  final bool standalone;

  const PreferredVendorSection({
    super.key,
    required this.serviceId,
    required this.parentNodeId,
    required this.lat,
    required this.lng,
    required this.selectedVendorId,
    required this.onSelect,
    this.selectedDate,
    this.standalone = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(preferredVendorsForServiceProvider((
      serviceId: serviceId,
      parentNodeId: parentNodeId,
      lat: lat,
      lng: lng,
    )));

    return vendorsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (vendors) {
        if (vendors.isEmpty) return const SizedBox.shrink();

        final tt = Theme.of(context).textTheme;
        final selectedName = vendors
            .where((v) => v.id == selectedVendorId)
            .map((v) => v.businessName)
            .firstOrNull;

        final hp = standalone ? 20.0 : 0.0;
        final fadeColor = standalone
            ? AppColors.background
            : Theme.of(context).colorScheme.surface;

        // Date string used for the vendor busy check.
        final dateArg = selectedDate ?? DateTime.now();
        final dateStr =
            '${dateArg.year}-${dateArg.month.toString().padLeft(2, '0')}-${dateArg.day.toString().padLeft(2, '0')}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section header ──────────────────────────────────────────────
            Padding(
              padding:
                  EdgeInsets.fromLTRB(hp, standalone ? 28.0 : 0.0, hp, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Preferred Vendors',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  const _OptionalBadge(),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: selectedVendorId != null && selectedName != null
                        ? _SelectedBadge(
                            key: ValueKey(selectedVendorId),
                            name: selectedName,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // ── Hint text ──────────────────────────────────────────────────
            Padding(
              padding:
                  EdgeInsets.fromLTRB(hp, 5, hp, standalone ? 14.0 : 10.0),
              child: Text(
                vendors.length > 1
                    ? 'Scroll to see all ${vendors.length} options'
                    : 'Select a preferred vendor for personalized service',
                style: tt.bodySmall?.copyWith(color: AppColors.textHint),
              ),
            ),

            // ── Scrollable list with fade edge ─────────────────────────────
            SizedBox(
              height: _VendorCard.cardHeight,
              child: Stack(
                children: [
                  ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: hp),
                    scrollDirection: Axis.horizontal,
                    itemCount: vendors.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return _VendorCard(
                          label: 'No Preference',
                          sublabel: 'Any available vendor',
                          feeLabel: null,
                          isSelected: selectedVendorId == null,
                          onTap: () => onSelect(null, null, 0.0),
                        );
                      }
                      final v = vendors[i - 1];
                      return _VendorCard(
                        label: v.businessName,
                        sublabel: v.rating != null
                            ? '★ ${v.rating!.toStringAsFixed(1)}'
                            : null,
                        feeLabel: v.preferredVendorFee > 0
                            ? '+₹${v.preferredVendorFee.toInt()}'
                            : null,
                        isSelected: selectedVendorId == v.id,
                        onTap: () =>
                            onSelect(v.id, v.businessName, v.preferredVendorFee),
                        vendorId: v.id,
                        date: dateStr,
                      );
                    },
                  ),

                  // Right-edge fade
                  if (vendors.length > 1)
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
                                fadeColor.withAlpha(0),
                                fadeColor,
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
      },
    );
  }
}

// ── "Optional" pill badge ─────────────────────────────────────────────────────

class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold.withAlpha(24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
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

// ── Selected vendor name badge ────────────────────────────────────────────────

class _SelectedBadge extends StatelessWidget {
  final String name;
  const _SelectedBadge({super.key, required this.name});

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
          const Icon(Icons.check_circle_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual vendor card ────────────────────────────────────────────────────

class _VendorCard extends ConsumerWidget {
  static const double cardWidth = 172.0;
  static const double cardHeight = 162.0;

  final String label;
  final String? sublabel;
  final String? feeLabel;
  final bool isSelected;
  final VoidCallback onTap;
  // Busy check — null on the "No Preference" card
  final String? vendorId;
  final String? date;

  const _VendorCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.sublabel,
    this.feeLabel,
    this.vendorId,
    this.date,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final hasDesc = sublabel != null;

    // Resolve busy status for real vendor cards; null = loading or no check.
    bool? isBusyValue;
    if (vendorId != null && date != null) {
      isBusyValue = ref
          .watch(vendorBusyProvider((
            vendorId: vendorId!,
            date: date!,
          )))
          .valueOrNull;
    }

    final bool isBusy = isBusyValue ?? false;
    // Busy vendor: force-deselect to avoid stale highlight.
    final bool effectiveSelected = isSelected && !isBusy;

    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: effectiveSelected ? AppColors.goldLight : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: effectiveSelected ? AppColors.gold : AppColors.border,
            width: effectiveSelected ? 1.5 : 1.0,
          ),
          boxShadow: effectiveSelected
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
                    label,
                    style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: effectiveSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: hasDesc ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _Checkbox(isSelected: effectiveSelected),
              ],
            ),

            // Description / rating
            if (hasDesc) ...[
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  sublabel!,
                  style: tt.bodySmall?.copyWith(
                    color: effectiveSelected
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

            // Fee
            if (feeLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                feeLabel!,
                style: tt.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color:
                      effectiveSelected ? AppColors.gold : AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],

            // Availability: AVAILABLE or VENDOR CURRENTLY BUSY
            // Only shown once the RPC result is known (isBusyValue != null).
            if (vendorId != null && date != null && isBusyValue != null) ...[
              const SizedBox(height: 6),
              _BusyBadge(isBusy: isBusy),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Availability badge ────────────────────────────────────────────────────────

class _BusyBadge extends StatelessWidget {
  final bool isBusy;
  const _BusyBadge({required this.isBusy});

  @override
  Widget build(BuildContext context) {
    final color = isBusy ? AppColors.error : AppColors.success;
    final label = isBusy ? 'Vendor Currently Busy' : 'Available';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
