import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_activity.dart';
import '../../domain/models/instahelp_mode.dart';
import '../providers/instahelp_vendor_providers.dart';
import '../widgets/duration_form_dialog.dart';
import '../widgets/activity_form_dialog.dart';
import '../widgets/slot_config_section.dart';
import '../widgets/financial_config_section.dart';
import '../widgets/date_override_section.dart';

class VendorInstaHelpPage extends ConsumerStatefulWidget {
  const VendorInstaHelpPage({super.key});

  @override
  ConsumerState<VendorInstaHelpPage> createState() => _VendorInstaHelpPageState();
}

class _VendorInstaHelpPageState extends ConsumerState<VendorInstaHelpPage>
    with SingleTickerProviderStateMixin {
  late final TabController _innerTab;

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 3, vsync: this);
  }

  void _setShellActions() {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;
    ref.read(vendorShellActionsProvider.notifier).state = [
      IconButton(
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh',
        onPressed: () => ref.invalidate(vendorModesProvider(vendor.id)),
      ),
    ];
  }

  @override
  void dispose() {
    _innerTab.dispose();
    ref.read(vendorShellActionsProvider.notifier).state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendor = ref.watch(currentVendorUserProvider);
    if (vendor == null) {
      return const Center(child: CircularProgressIndicator());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setShellActions();
    });

    final modesAsync = ref.watch(vendorModesProvider(vendor.id));

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('InstaHelp',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('On-demand & scheduled services',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ]),
          ),
          Expanded(
            child: _InstaHelpConfigTab(
              vendorId: vendor.id,
              modesAsync: modesAsync,
              innerTab: _innerTab,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Config tab ────────────────────────────────────────────────────────────────

class _InstaHelpConfigTab extends ConsumerWidget {
  final String vendorId;
  final AsyncValue<List<InstaHelpMode>> modesAsync;
  final TabController innerTab;

  const _InstaHelpConfigTab({
    required this.vendorId,
    required this.modesAsync,
    required this.innerTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEligible =
        ref.watch(vendorInstaHelpEligibilityProvider(vendorId)).valueOrNull ?? true;
    return Column(
      children: [
        // Inner TabBar: Scheduled | Instant | Car Wash
        modesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, s) => const SizedBox.shrink(),
          data: (modes) => modes.isEmpty
              ? const SizedBox.shrink()
              : Material(
                  color: Colors.white,
                  child: TabBar(
                    controller: innerTab,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    dividerColor: AppColors.border,
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabs: const [
                      Tab(text: 'Scheduled'),
                      Tab(text: 'Instant'),
                      Tab(text: 'Car Wash'),
                    ],
                  ),
                ),
        ),
        Expanded(
          child: modesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Failed to load: $e',
                  style: const TextStyle(color: AppColors.error, fontSize: 14)),
            ),
            data: (modes) {
              if (modes.isEmpty) {
                return _EnableInstaHelpCard(vendorId: vendorId);
              }

              InstaHelpMode? findMode(String type) {
                try {
                  return modes.firstWhere((m) => m.modeType == type);
                } catch (_) {
                  return null;
                }
              }

              final scheduled = findMode('scheduled');
              final instant = findMode('instant');
              final carWash = findMode('car_wash');

              return TabBarView(
                controller: innerTab,
                children: [
                  scheduled != null
                      ? _ModeTabContent(mode: scheduled, vendorId: vendorId, showSlotConfig: true, isEligible: isEligible)
                      : const _ModeNotFound(),
                  instant != null
                      ? _ModeTabContent(mode: instant, vendorId: vendorId, showSlotConfig: false, isEligible: isEligible)
                      : const _ModeNotFound(),
                  carWash != null
                      ? _ModeTabContent(mode: carWash, vendorId: vendorId, showSlotConfig: false, isEligible: isEligible)
                      : const _ModeNotFound(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Enable prompt ─────────────────────────────────────────────────────────────

class _EnableInstaHelpCard extends ConsumerStatefulWidget {
  final String vendorId;
  const _EnableInstaHelpCard({required this.vendorId});

  @override
  ConsumerState<_EnableInstaHelpCard> createState() => _EnableInstaHelpCardState();
}

class _EnableInstaHelpCardState extends ConsumerState<_EnableInstaHelpCard> {
  bool _loading = false;

  Future<void> _enable() async {
    setState(() => _loading = true);
    try {
      await ref.read(vendorModesProvider(widget.vendorId).notifier).initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flash_on_rounded, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            const Text('InstaHelp Not Set Up',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            const Text(
              'Enable InstaHelp to offer on-demand and scheduled\nservices directly to customers in your area.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _loading ? null : _enable,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.flash_on_rounded, size: 18),
              label: const Text('Enable InstaHelp'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode tab content ──────────────────────────────────────────────────────────

class _ModeTabContent extends ConsumerWidget {
  final InstaHelpMode mode;
  final String vendorId;
  final bool showSlotConfig;
  final bool isEligible;
  const _ModeTabContent({required this.mode, required this.vendorId, required this.showSlotConfig, required this.isEligible});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (!isEligible)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.error, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An active InstaHelp subscription is required to add or activate services.',
                  style: TextStyle(fontSize: 13, color: AppColors.error),
                ),
              ),
            ]),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: Text('${mode.displayName} Mode Active',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text(
              mode.isActive ? 'Visible to customers in your area' : 'Hidden from customers',
              style: TextStyle(fontSize: 13, color: mode.isActive ? AppColors.success : AppColors.textSecondary),
            ),
            value: mode.isActive,
            onChanged: (!isEligible && !mode.isActive)
                ? null
                : (v) => ref.read(vendorModesProvider(vendorId).notifier).toggleActive(mode.id, isActive: v),
            activeThumbColor: AppColors.success,
          ),
        ),
        const SizedBox(height: 20),
        VendorFinancialConfigSection(modeId: mode.id),
        const SizedBox(height: 20),
        _DurationSection(modeId: mode.id, showSlotSchedule: showSlotConfig, isEligible: isEligible),
        if (showSlotConfig) ...[
          const SizedBox(height: 20),
          VendorSlotConfigSection(modeId: mode.id),
        ],
        const SizedBox(height: 20),
        _ActivitiesSection(modeId: mode.id, isEligible: isEligible),
        const SizedBox(height: 20),
        VendorDateOverrideSection(modeId: mode.id),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ModeNotFound extends StatelessWidget {
  const _ModeNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Mode not configured', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
    );
  }
}

// ── Duration section ──────────────────────────────────────────────────────────

class _DurationSection extends ConsumerWidget {
  final String modeId;
  final bool showSlotSchedule;
  final bool isEligible;
  const _DurationSection({required this.modeId, required this.showSlotSchedule, required this.isEligible});

  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  void _openCreate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorDurationFormDialog(
        showSlotSchedule: showSlotSchedule,
        onSave: ({
          required label, required durationMinutes, required price,
          required discountType, required discountValue, required isActive,
          required slotStartTime, required slotEndTime,
          required slotIntervalMinutes, required maxBookingsPerSlot,
        }) =>
            ref.read(vendorDurationsProvider(modeId).notifier).create(
              label: label, durationMinutes: durationMinutes, price: price,
              discountType: discountType, discountValue: discountValue, isActive: isActive,
              slotStartTime: slotStartTime, slotEndTime: slotEndTime,
              slotIntervalMinutes: slotIntervalMinutes, maxBookingsPerSlot: maxBookingsPerSlot,
            ),
      ),
    );
  }

  void _openEdit(BuildContext context, WidgetRef ref, InstaHelpDuration duration) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorDurationFormDialog(
        existing: duration,
        showSlotSchedule: showSlotSchedule,
        onSave: ({
          required label, required durationMinutes, required price,
          required discountType, required discountValue, required isActive,
          required slotStartTime, required slotEndTime,
          required slotIntervalMinutes, required maxBookingsPerSlot,
        }) =>
            ref.read(vendorDurationsProvider(modeId).notifier).update(duration.id,
              label: label, durationMinutes: durationMinutes, price: price,
              discountType: discountType, discountValue: discountValue, isActive: isActive,
              slotStartTime: slotStartTime, slotEndTime: slotEndTime,
              slotIntervalMinutes: slotIntervalMinutes, maxBookingsPerSlot: maxBookingsPerSlot,
            ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, InstaHelpDuration d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Duration'),
        content: Text('Delete "${d.label}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(vendorDurationsProvider(modeId).notifier).delete(d.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationsAsync = ref.watch(vendorDurationsProvider(modeId));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(children: [
              const Icon(Icons.timer_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Duration & Pricing',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              FilledButton.icon(
                onPressed: isEligible ? () => _openCreate(context, ref) : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Duration'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          durationsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (durations) {
              if (durations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Column(children: [
                      const Icon(Icons.timer_off_rounded, size: 36, color: AppColors.textSecondary),
                      const SizedBox(height: 8),
                      const Text('No duration options yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('Add your first duration option above',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ]),
                  ),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.background),
                  headingTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  dataTextStyle: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('DURATION')),
                    DataColumn(label: Text('PRICE'), numeric: true),
                    DataColumn(label: Text('DISCOUNT')),
                    DataColumn(label: Text('FINAL'), numeric: true),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: durations.map((d) => DataRow(cells: [
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${d.durationMinutes} min', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    )),
                    DataCell(Text(_currency.format(d.price))),
                    DataCell(_DiscountBadge(d: d)),
                    DataCell(Text(_currency.format(d.finalPrice),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success))),
                    DataCell(Switch(
                      value: d.isActive,
                      onChanged: (v) => ref.read(vendorDurationsProvider(modeId).notifier).toggleActive(d.id, isActive: v),
                      activeTrackColor: AppColors.success,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 17, color: AppColors.primary),
                        tooltip: 'Edit',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openEdit(context, ref, d),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.error),
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _confirmDelete(context, ref, d),
                      ),
                    ])),
                  ])).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final InstaHelpDuration d;
  const _DiscountBadge({required this.d});

  @override
  Widget build(BuildContext context) {
    if (!d.hasDiscount) return const Text('None', style: TextStyle(color: AppColors.textSecondary, fontSize: 12));
    final label = d.discountType == 'percentage'
        ? '${d.discountValue.toStringAsFixed(0)}% off'
        : '₹${d.discountValue.toStringAsFixed(0)} off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Activities section ────────────────────────────────────────────────────────

class _ActivitiesSection extends ConsumerWidget {
  final String modeId;
  final bool isEligible;
  const _ActivitiesSection({required this.modeId, required this.isEligible});

  void _openCreate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorActivityFormDialog(
        onSave: ({required title, required includedItems, required excludedItems, required isActive}) =>
            ref.read(vendorActivitiesProvider(modeId).notifier).create(
              title: title, includedItems: includedItems, excludedItems: excludedItems, isActive: isActive,
            ),
      ),
    );
  }

  void _openEdit(BuildContext context, WidgetRef ref, InstaHelpActivity activity) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorActivityFormDialog(
        existing: activity,
        onSave: ({required title, required includedItems, required excludedItems, required isActive}) =>
            ref.read(vendorActivitiesProvider(modeId).notifier).update(activity.id,
              title: title, includedItems: includedItems, excludedItems: excludedItems, isActive: isActive,
            ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, InstaHelpActivity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Activity'),
        content: Text('Delete "${a.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(vendorActivitiesProvider(modeId).notifier).delete(a.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(vendorActivitiesProvider(modeId));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(children: [
              const Icon(Icons.layers_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Activity Groups',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              FilledButton.icon(
                onPressed: isEligible ? () => _openCreate(context, ref) : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Group'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          activitiesAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (activities) {
              if (activities.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: Text('No activity groups yet',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14))),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length,
                separatorBuilder: (_, i) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final a = activities[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: a.isActive ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              if (a.includedItems.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Included: ${a.includedItems.join(', ')}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                              if (a.excludedItems.isNotEmpty)
                                Text('Excluded: ${a.excludedItems.join(', ')}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.error)),
                            ],
                          ),
                        ),
                        Switch(
                          value: a.isActive,
                          onChanged: (v) => ref.read(vendorActivitiesProvider(modeId).notifier).toggleActive(a.id, isActive: v),
                          activeTrackColor: AppColors.success,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 17, color: AppColors.primary),
                          tooltip: 'Edit',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openEdit(context, ref, a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.error),
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _confirmDelete(context, ref, a),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
