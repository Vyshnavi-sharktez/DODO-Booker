import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/instahelp_providers.dart';
import '../../domain/models/instahelp_activity.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_mode.dart';
import '../widgets/activity_form_dialog.dart';
import '../widgets/duration_form_dialog.dart';
import '../widgets/slot_config_section.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _vihVendorListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await Supabase.instance.client
      .from('vendors')
      .select('id, business_name')
      .eq('is_active', true)
      .order('business_name');
  return List<Map<String, dynamic>>.from(data as List);
});

final _vihSelectedVendorIdProvider = StateProvider<String?>((ref) => null);

// ── Page ─────────────────────────────────────────────────────────────────────

class VendorInstaHelpPage extends ConsumerStatefulWidget {
  const VendorInstaHelpPage({super.key});

  @override
  ConsumerState<VendorInstaHelpPage> createState() =>
      _VendorInstaHelpPageState();
}

class _VendorInstaHelpPageState extends ConsumerState<VendorInstaHelpPage> {
  final _searchCtrl = TextEditingController();
  String _vendorSearch = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(_vihVendorListProvider);
    final selectedVendorId = ref.watch(_vihSelectedVendorIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Vendor picker ────────────────────────────────────────────────
          Container(
            width: 260,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                const _PanelHeader(title: 'Vendors'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search vendors…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onChanged: (v) =>
                        setState(() => _vendorSearch = v.trim()),
                  ),
                ),
                Expanded(
                  child: vendorsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13)),
                    ),
                    data: (vendors) {
                      final filtered = _vendorSearch.isEmpty
                          ? vendors
                          : vendors
                              .where((v) => (v['business_name'] as String)
                                  .toLowerCase()
                                  .contains(_vendorSearch.toLowerCase()))
                              .toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text('No vendors found',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        );
                      }

                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final v = filtered[i];
                          final id = v['id'] as String;
                          final name = v['business_name'] as String;
                          final isSelected = id == selectedVendorId;

                          return ColoredBox(
                            color: isSelected
                                ? const Color(0xFF1E3A5F)
                                : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: isSelected
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : AppColors.border,
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              onTap: () => ref
                                  .read(_vihSelectedVendorIdProvider.notifier)
                                  .state = id,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── InstaHelp content ────────────────────────────────────────────
          Expanded(
            child: selectedVendorId == null
                ? const _EmptySelection()
                : Builder(builder: (context) {
                    final vendorName = vendorsAsync.valueOrNull
                            ?.firstWhere(
                              (v) => v['id'] == selectedVendorId,
                              orElse: () => {'business_name': ''},
                            )['business_name'] as String? ??
                        '';
                    return _VendorInstaHelpContent(
                      key: ValueKey(selectedVendorId),
                      vendorId: selectedVendorId,
                      vendorName: vendorName,
                    );
                  }),
          ),
        ],
      ),
    );
  }
}

// ── Vendor InstaHelp content ──────────────────────────────────────────────────

class _VendorInstaHelpContent extends ConsumerStatefulWidget {
  const _VendorInstaHelpContent({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });
  final String vendorId;
  final String vendorName;

  @override
  ConsumerState<_VendorInstaHelpContent> createState() =>
      _VendorInstaHelpContentState();
}

class _VendorInstaHelpContentState
    extends ConsumerState<_VendorInstaHelpContent>
    with SingleTickerProviderStateMixin {
  TabController? _tab;
  bool? _hasSubscription;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _checkSubscription();
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  Future<void> _checkSubscription() async {
    try {
      final data = await Supabase.instance.client
          .from('vendor_subscriptions')
          .select('id, subscription_plans(id, permissions)')
          .eq('vendor_id', widget.vendorId)
          .eq('status', 'active')
          .maybeSingle();
      if (mounted) {
        final plan = data?['subscription_plans'] as Map<String, dynamic>?;
        final perms = (plan?['permissions'] as Map<String, dynamic>?) ?? {};
        final hasFeature = perms['allow_instahelp'] == true;
        setState(() => _hasSubscription = data != null && hasFeature);
      }
    } catch (_) {
      if (mounted) setState(() => _hasSubscription = false);
    }
  }

  Future<void> _initVendorModes() async {
    setState(() => _initializing = true);
    try {
      await ref
          .read(instaHelpRepositoryProvider)
          .initVendorModes(widget.vendorId);
      ref.invalidate(instaHelpVendorModesProvider(widget.vendorId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Init failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _syncTabController(List<InstaHelpMode> modes) {
    if (_tab == null || _tab!.length != modes.length) {
      _tab?.dispose();
      _tab = TabController(length: modes.length, vsync: this);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modesAsync =
        ref.watch(instaHelpVendorModesProvider(widget.vendorId));

    // Sync tab controller before the widget tree so the header TabBar
    // already has a valid controller when it renders.
    modesAsync.whenData((modes) {
      if (modes.isNotEmpty) _syncTabController(modes);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.flash_on_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.vendorName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Vendor InstaHelp Configuration',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                // Subscription warning
                if (_hasSubscription == false) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFFB300)
                              .withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 18, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No Active InstaHelp Subscription',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E)),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'This vendor does not have an active subscription that includes '
                                'InstaHelp. You can still configure their settings.',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF78350F)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_tab != null)
                  modesAsync.maybeWhen(
                  data: (modes) => modes.isEmpty
                      ? const SizedBox.shrink()
                      : TabBar(
                          controller: _tab!,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: AppColors.textSecondary,
                          indicatorColor: AppColors.primary,
                          indicatorWeight: 2.5,
                          labelStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          unselectedLabelStyle:
                              const TextStyle(fontSize: 14),
                          tabs: modes
                              .map((m) => Tab(text: m.displayName))
                              .toList(),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: modesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Failed to load: $e',
                        style: TextStyle(
                            color: AppColors.error, fontSize: 14)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(
                          instaHelpVendorModesProvider(widget.vendorId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (modes) {
                if (modes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flash_off_rounded,
                            size: 56, color: AppColors.textSecondary),
                        const SizedBox(height: 16),
                        const Text(
                          'InstaHelp not configured for this vendor',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Initialize to create vendor-specific InstaHelp settings.',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed:
                              _initializing ? null : _initVendorModes,
                          icon: _initializing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.flash_on_rounded,
                                  size: 16),
                          label: Text(_initializing
                              ? 'Initializing…'
                              : 'Initialize InstaHelp'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary),
                        ),
                      ],
                    ),
                  );
                }

                _syncTabController(modes);
                if (_tab == null) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                return TabBarView(
                  controller: _tab,
                  children: modes.map((m) {
                    final showSlot = m.modeType != 'instant';
                    return _VihModeTabContent(
                      modeId: m.id,
                      showSlotConfig: showSlot,
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode tab content ──────────────────────────────────────────────────────────

class _VihModeTabContent extends StatelessWidget {
  final String modeId;
  final bool showSlotConfig;
  const _VihModeTabContent(
      {required this.modeId, this.showSlotConfig = true});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _VihDurationSection(modeId: modeId, showSlotSchedule: showSlotConfig),
        const SizedBox(height: 24),
        SlotConfigSection(modeId: modeId, showGlobalConfig: showSlotConfig),
        const SizedBox(height: 24),
        _VihActivitiesSection(modeId: modeId),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Duration section ──────────────────────────────────────────────────────────

class _VihDurationSection extends ConsumerWidget {
  final String modeId;
  final bool showSlotSchedule;
  const _VihDurationSection(
      {required this.modeId, this.showSlotSchedule = true});

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  void _openCreate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DurationFormDialog(
        showSlotSchedule: showSlotSchedule,
        onSave: ({
          required label,
          required durationMinutes,
          required price,
          required discountType,
          required discountValue,
          required isActive,
          required slotStartTime,
          required slotEndTime,
          required slotIntervalMinutes,
          required maxBookingsPerSlot,
        }) =>
            ref.read(instaHelpDurationsProvider(modeId).notifier).create(
                  label: label,
                  durationMinutes: durationMinutes,
                  price: price,
                  discountType: discountType,
                  discountValue: discountValue,
                  isActive: isActive,
                  slotStartTime: slotStartTime,
                  slotEndTime: slotEndTime,
                  slotIntervalMinutes: slotIntervalMinutes,
                  maxBookingsPerSlot: maxBookingsPerSlot,
                ),
      ),
    );
  }

  void _openEdit(
      BuildContext context, WidgetRef ref, InstaHelpDuration duration) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DurationFormDialog(
        existing: duration,
        showSlotSchedule: showSlotSchedule,
        onSave: ({
          required label,
          required durationMinutes,
          required price,
          required discountType,
          required discountValue,
          required isActive,
          required slotStartTime,
          required slotEndTime,
          required slotIntervalMinutes,
          required maxBookingsPerSlot,
        }) =>
            ref.read(instaHelpDurationsProvider(modeId).notifier).update(
                  duration.id,
                  label: label,
                  durationMinutes: durationMinutes,
                  price: price,
                  discountType: discountType,
                  discountValue: discountValue,
                  isActive: isActive,
                  slotStartTime: slotStartTime,
                  slotEndTime: slotEndTime,
                  slotIntervalMinutes: slotIntervalMinutes,
                  maxBookingsPerSlot: maxBookingsPerSlot,
                ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      InstaHelpDuration duration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Duration'),
        content: Text('Delete "${duration.label}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dlg).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dlg).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(instaHelpDurationsProvider(modeId).notifier)
            .delete(duration.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppColors.error));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationsAsync = ref.watch(instaHelpDurationsProvider(modeId));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Duration & Pricing',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _openCreate(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Duration'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          durationsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $e',
                    style: TextStyle(color: AppColors.error))),
            data: (durations) {
              if (durations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.timer_off_rounded,
                          size: 40, color: AppColors.textSecondary),
                      const SizedBox(height: 10),
                      Text('No duration options yet',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14)),
                    ]),
                  ),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(AppColors.background),
                  headingTextStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                  dataTextStyle: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('DURATION')),
                    DataColumn(label: Text('ORIGINAL PRICE'), numeric: true),
                    DataColumn(label: Text('DISCOUNT')),
                    DataColumn(
                        label: Text('DISCOUNT AMT'), numeric: true),
                    DataColumn(label: Text('FINAL PRICE'), numeric: true),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('POSITION')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: durations.asMap().entries.map((entry) {
                    final i = entry.key;
                    final d = entry.value;
                    return DataRow(cells: [
                      DataCell(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(d.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text('${d.durationMinutes} min',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        ],
                      )),
                      DataCell(Text(_currency.format(d.price))),
                      DataCell(_VihDiscountBadge(duration: d)),
                      DataCell(Text(
                        d.hasDiscount
                            ? _currency.format(d.discountAmount)
                            : '—',
                        style: TextStyle(
                            color: d.hasDiscount
                                ? AppColors.error
                                : AppColors.textSecondary),
                      )),
                      DataCell(Text(
                        _currency.format(d.finalPrice),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.success),
                      )),
                      DataCell(Switch(
                        value: d.isActive,
                        onChanged: (v) => ref
                            .read(instaHelpDurationsProvider(modeId)
                                .notifier)
                            .toggleActive(d.id, isActive: v),
                        activeTrackColor: AppColors.success,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      )),
                      DataCell(durations.length > 1
                          ? _VihPositionControls(
                              position: i,
                              total: durations.length,
                              onMoveUp: i > 0
                                  ? () {
                                      final r = [...durations]
                                        ..removeAt(i)
                                        ..insert(i - 1, d);
                                      ref
                                          .read(instaHelpDurationsProvider(
                                                  modeId)
                                              .notifier)
                                          .reorder(r);
                                    }
                                  : null,
                              onMoveDown: i < durations.length - 1
                                  ? () {
                                      final r = [...durations]
                                        ..removeAt(i)
                                        ..insert(i + 1, d);
                                      ref
                                          .read(instaHelpDurationsProvider(
                                                  modeId)
                                              .notifier)
                                          .reorder(r);
                                    }
                                  : null,
                              onMoveTo: (target) {
                                final r = [...durations]
                                  ..removeAt(i)
                                  ..insert(target, d);
                                ref
                                    .read(instaHelpDurationsProvider(modeId)
                                        .notifier)
                                    .reorder(r);
                              },
                            )
                          : Text('1',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13))),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_rounded,
                                size: 17, color: AppColors.primary),
                            tooltip: 'Edit',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _openEdit(context, ref, d),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 17, color: AppColors.error),
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _confirmDelete(context, ref, d),
                          ),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Activities section ────────────────────────────────────────────────────────

class _VihActivitiesSection extends ConsumerWidget {
  final String modeId;
  const _VihActivitiesSection({required this.modeId});

  void _openCreate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityFormDialog(
        onSave: ({
          required title,
          required includedItems,
          required excludedItems,
          required isActive,
        }) =>
            ref.read(instaHelpActivitiesProvider(modeId).notifier).create(
                  title: title,
                  includedItems: includedItems,
                  excludedItems: excludedItems,
                  isActive: isActive,
                ),
      ),
    );
  }

  void _openEdit(
      BuildContext context, WidgetRef ref, InstaHelpActivity activity) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityFormDialog(
        existing: activity,
        onSave: ({
          required title,
          required includedItems,
          required excludedItems,
          required isActive,
        }) =>
            ref.read(instaHelpActivitiesProvider(modeId).notifier).update(
                  activity.id,
                  title: title,
                  includedItems: includedItems,
                  excludedItems: excludedItems,
                  isActive: isActive,
                ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      InstaHelpActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Activity'),
        content: Text('Delete "${activity.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dlg).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dlg).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(instaHelpActivitiesProvider(modeId).notifier)
            .delete(activity.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppColors.error));
        }
      }
    }
  }

  Widget _itemList(List<String> items, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(instaHelpActivitiesProvider(modeId));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                const Icon(Icons.layers_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Activity Groups',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _openCreate(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Group'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          activitiesAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.error))),
            data: (activities) {
              if (activities.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text('No activity groups yet',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14)),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final a = activities[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: a.isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              if (a.includedItems.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 11,
                                      color: AppColors.success),
                                  const SizedBox(width: 4),
                                  Text('Included',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w600)),
                                ]),
                                _itemList(
                                    a.includedItems, AppColors.success),
                              ],
                              if (a.excludedItems.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  const Icon(
                                      Icons.do_not_disturb_alt_rounded,
                                      size: 11,
                                      color: AppColors.error),
                                  const SizedBox(width: 4),
                                  Text('Excluded',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.error,
                                          fontWeight: FontWeight.w600)),
                                ]),
                                _itemList(
                                    a.excludedItems, AppColors.error),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (activities.length > 1)
                          _VihPositionControls(
                            position: i,
                            total: activities.length,
                            onMoveUp: i > 0
                                ? () {
                                    final r = [...activities]
                                      ..removeAt(i)
                                      ..insert(i - 1, a);
                                    ref
                                        .read(instaHelpActivitiesProvider(
                                                modeId)
                                            .notifier)
                                        .reorder(r);
                                  }
                                : null,
                            onMoveDown: i < activities.length - 1
                                ? () {
                                    final r = [...activities]
                                      ..removeAt(i)
                                      ..insert(i + 1, a);
                                    ref
                                        .read(instaHelpActivitiesProvider(
                                                modeId)
                                            .notifier)
                                        .reorder(r);
                                  }
                                : null,
                            onMoveTo: (target) {
                              final r = [...activities]
                                ..removeAt(i)
                                ..insert(target, a);
                              ref
                                  .read(instaHelpActivitiesProvider(modeId)
                                      .notifier)
                                  .reorder(r);
                            },
                          ),
                        Switch(
                          value: a.isActive,
                          onChanged: (v) => ref
                              .read(instaHelpActivitiesProvider(modeId)
                                  .notifier)
                              .toggleActive(a.id, isActive: v),
                          activeTrackColor: AppColors.success,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded,
                              size: 17, color: AppColors.primary),
                          tooltip: 'Edit',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openEdit(context, ref, a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 17, color: AppColors.error),
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _confirmDelete(context, ref, a),
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

// ── Shared small widgets ──────────────────────────────────────────────────────

class _VihDiscountBadge extends StatelessWidget {
  final InstaHelpDuration duration;
  const _VihDiscountBadge({required this.duration});

  @override
  Widget build(BuildContext context) {
    if (!duration.hasDiscount) {
      return Text('None',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12));
    }
    final label = duration.discountType == 'percentage'
        ? '${duration.discountValue.toStringAsFixed(0)}% off'
        : '₹${duration.discountValue.toStringAsFixed(0)} off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: AppColors.error,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _VihPositionControls extends StatelessWidget {
  const _VihPositionControls({
    required this.position,
    required this.total,
    required this.onMoveTo,
    this.onMoveUp,
    this.onMoveDown,
  });
  final int position;
  final int total;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final void Function(int target) onMoveTo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VihArrow(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'Move up',
            onTap: onMoveUp),
        const SizedBox(width: 2),
        Builder(
          builder: (ctx) => Tooltip(
            message: 'Jump to position',
            child: PopupMenuButton<int>(
              tooltip: '',
              onSelected: (target) async {
                final confirmed = await showDialog<bool>(
                  context: ctx,
                  builder: (dlg) => AlertDialog(
                    title: const Text('Move to Position'),
                    content: Text('Move to position ${target + 1}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(dlg).pop(false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.of(dlg).pop(true),
                          child: const Text('Move')),
                    ],
                  ),
                );
                if (confirmed == true) onMoveTo(target);
              },
              offset: const Offset(0, 28),
              itemBuilder: (_) => [
                for (int p = 0; p < total; p++)
                  if (p != position)
                    PopupMenuItem<int>(
                      value: p,
                      height: 36,
                      child: Text('Position ${p + 1}',
                          style: const TextStyle(fontSize: 13)),
                    ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${position + 1}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        _VihArrow(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Move down',
            onTap: onMoveDown),
      ],
    );
  }
}

class _VihArrow extends StatelessWidget {
  const _VihArrow(
      {required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 18,
              color: onTap != null
                  ? AppColors.textSecondary
                  : AppColors.border),
        ),
      ),
    );
  }
}

// ── Shared layout widgets ─────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flash_on_rounded, size: 56, color: AppColors.border),
          SizedBox(height: 16),
          Text('Select a vendor',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          SizedBox(height: 4),
          Text('Choose a vendor from the list to manage their InstaHelp config.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
