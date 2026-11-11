import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/instahelp_providers.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_activity.dart';
import '../../domain/models/instahelp_financial_config.dart';
import '../widgets/duration_form_dialog.dart';
import '../widgets/activity_form_dialog.dart';
import '../widgets/slot_config_section.dart';

class InstaHelpPage extends ConsumerStatefulWidget {
  const InstaHelpPage({super.key});

  @override
  ConsumerState<InstaHelpPage> createState() => _InstaHelpPageState();
}

class _InstaHelpPageState extends ConsumerState<InstaHelpPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modesAsync = ref.watch(instaHelpModesProvider);

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
                        const Text(
                          'InstaHelp Configuration',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Manage duration pricing and activity lists per mode',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tab,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  tabs: const [
                    Tab(text: 'Scheduled'),
                    Tab(text: 'Instant'),
                    Tab(text: 'Car Wash'),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: modesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Failed to load modes: $e',
                        style:
                            TextStyle(color: AppColors.error, fontSize: 14)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(instaHelpModesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (modes) {
                if (modes.isEmpty) {
                  return const Center(
                    child: Text(
                      'Modes not seeded. Apply the migration and reload.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                final scheduled = modes.firstWhere(
                    (m) => m.modeType == 'scheduled',
                    orElse: () => modes.first);
                final instant = modes.firstWhere(
                    (m) => m.modeType == 'instant',
                    orElse: () => modes.first);
                final carWash = modes.firstWhere(
                    (m) => m.modeType == 'car_wash',
                    orElse: () => modes.first);

                return TabBarView(
                  controller: _tab,
                  children: [
                    _ModeTabContent(modeId: scheduled.id, showSlotConfig: true),
                    _ModeTabContent(modeId: instant.id,   showSlotConfig: false),
                    _ModeTabContent(modeId: carWash.id,   showSlotConfig: true),
                  ],
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

class _ModeTabContent extends StatelessWidget {
  final String modeId;
  final bool showSlotConfig;
  const _ModeTabContent({required this.modeId, this.showSlotConfig = true});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _FinancialConfigSection(modeId: modeId),
        const SizedBox(height: 24),
        _DurationSection(modeId: modeId, showSlotSchedule: showSlotConfig),
        const SizedBox(height: 24),
        SlotConfigSection(modeId: modeId, showGlobalConfig: showSlotConfig),
        const SizedBox(height: 24),
        _ActivitiesSection(modeId: modeId),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Duration & Pricing section ────────────────────────────────────────────────

class _DurationSection extends ConsumerWidget {
  final String modeId;
  final bool showSlotSchedule;
  const _DurationSection({required this.modeId, this.showSlotSchedule = true});

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

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, InstaHelpDuration duration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Duration'),
        content: Text(
            'Delete "${duration.label}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Delete failed: $e'),
                backgroundColor: AppColors.error),
          );
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
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                Icon(Icons.timer_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Duration & Pricing',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
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
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e',
                  style: TextStyle(color: AppColors.error)),
            ),
            data: (durations) {
              if (durations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.timer_off_rounded,
                            size: 40, color: AppColors.textSecondary),
                        const SizedBox(height: 10),
                        Text(
                          'No duration options yet',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add your first duration option above',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      AppColors.background),
                  headingTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  dataTextStyle: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('DURATION')),
                    DataColumn(label: Text('ORIGINAL PRICE'), numeric: true),
                    DataColumn(label: Text('DISCOUNT')),
                    DataColumn(label: Text('DISCOUNT AMT'), numeric: true),
                    DataColumn(label: Text('FINAL PRICE'), numeric: true),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('POSITION')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: durations.asMap().entries.map((entry) {
                    final i = entry.key;
                    final d = entry.value;
                    return DataRow(cells: [
                      DataCell(
                        Column(
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
                        ),
                      ),
                      DataCell(Text(_currency.format(d.price))),
                      DataCell(_DiscountBadge(duration: d)),
                      DataCell(
                        Text(
                          d.hasDiscount
                              ? _currency.format(d.discountAmount)
                              : '—',
                          style: TextStyle(
                            color: d.hasDiscount
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _currency.format(d.finalPrice),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.success),
                        ),
                      ),
                      DataCell(
                        Switch(
                          value: d.isActive,
                          onChanged: (v) => ref
                              .read(instaHelpDurationsProvider(modeId)
                                  .notifier)
                              .toggleActive(d.id, isActive: v),
                          activeTrackColor: AppColors.success,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      // Position controls
                      DataCell(
                        durations.length > 1
                            ? _PositionControls(
                                position: i,
                                total: durations.length,
                                onMoveUp: i > 0
                                    ? () {
                                        final reordered = [...durations]
                                          ..removeAt(i)
                                          ..insert(i - 1, d);
                                        ref
                                            .read(instaHelpDurationsProvider(modeId).notifier)
                                            .reorder(reordered);
                                      }
                                    : null,
                                onMoveDown: i < durations.length - 1
                                    ? () {
                                        final reordered = [...durations]
                                          ..removeAt(i)
                                          ..insert(i + 1, d);
                                        ref
                                            .read(instaHelpDurationsProvider(modeId).notifier)
                                            .reorder(reordered);
                                      }
                                    : null,
                                onMoveTo: (target) {
                                  final reordered = [...durations]
                                    ..removeAt(i)
                                    ..insert(target, d);
                                  ref
                                      .read(instaHelpDurationsProvider(modeId).notifier)
                                      .reorder(reordered);
                                },
                              )
                            : Text('1',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_rounded,
                                  size: 17,
                                  color: AppColors.primary),
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
                        ),
                      ),
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

// ── Financial Config section ──────────────────────────────────────────────────

class _FinancialConfigSection extends ConsumerStatefulWidget {
  final String modeId;
  const _FinancialConfigSection({required this.modeId});

  @override
  ConsumerState<_FinancialConfigSection> createState() =>
      _FinancialConfigSectionState();
}

class _FinancialConfigSectionState
    extends ConsumerState<_FinancialConfigSection> {
  final _gstCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _surgeValueCtrl = TextEditingController();
  final _serviceChargeValueCtrl = TextEditingController();

  bool _surgeFeeEnabled = false;
  String _surgeFeeType = 'percentage';
  bool _serviceChargeEnabled = false;
  String _serviceChargeType = 'fixed';
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _gstCtrl.dispose();
    _commissionCtrl.dispose();
    _surgeValueCtrl.dispose();
    _serviceChargeValueCtrl.dispose();
    super.dispose();
  }

  void _populate(InstaHelpFinancialConfig? cfg) {
    if (_loaded) return;
    _loaded = true;
    final c = cfg ?? InstaHelpFinancialConfig.defaultFor(widget.modeId);
    _gstCtrl.text = c.gstPercent > 0
        ? c.gstPercent.toStringAsFixed(c.gstPercent % 1 == 0 ? 0 : 2)
        : '';
    _commissionCtrl.text = c.platformCommissionPercent > 0
        ? c.platformCommissionPercent
            .toStringAsFixed(c.platformCommissionPercent % 1 == 0 ? 0 : 2)
        : '';
    _surgeValueCtrl.text = c.surgeFeeValue > 0
        ? c.surgeFeeValue.toStringAsFixed(c.surgeFeeValue % 1 == 0 ? 0 : 2)
        : '';
    _serviceChargeValueCtrl.text = c.serviceChargeValue > 0
        ? c.serviceChargeValue
            .toStringAsFixed(c.serviceChargeValue % 1 == 0 ? 0 : 2)
        : '';
    _surgeFeeEnabled = c.surgeFeeEnabled;
    _surgeFeeType = c.surgeFeeType;
    _serviceChargeEnabled = c.serviceChargeEnabled;
    _serviceChargeType = c.serviceChargeType;
  }

  Future<void> _save() async {
    final gst = double.tryParse(_gstCtrl.text.trim()) ?? 0;
    final commission = double.tryParse(_commissionCtrl.text.trim()) ?? 0;
    final surgeVal = double.tryParse(_surgeValueCtrl.text.trim()) ?? 0;
    final scVal = double.tryParse(_serviceChargeValueCtrl.text.trim()) ?? 0;

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref
          .read(instaHelpFinancialConfigProvider(widget.modeId).notifier)
          .save(
            gstPercent: gst,
            platformCommissionPercent: commission,
            surgeFeeEnabled: _surgeFeeEnabled,
            surgeFeeType: _surgeFeeType,
            surgeFeeValue: surgeVal,
            serviceChargeEnabled: _serviceChargeEnabled,
            serviceChargeType: _serviceChargeType,
            serviceChargeValue: scVal,
          );
      if (mounted) setState(() => _success = 'Financial config saved.');
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(instaHelpFinancialConfigProvider(widget.modeId));

    async.whenData(_populate);

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
                Icon(Icons.account_balance_wallet_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Financial Configuration',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (async.isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── GST & Commission ───────────────────────────────────
                  _SectionLabel('Tax & Commission'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _NumField(
                          controller: _gstCtrl,
                          label: 'GST / Tax %',
                          suffix: '%',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _NumField(
                          controller: _commissionCtrl,
                          label: 'Platform Commission %',
                          suffix: '%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Surge Fee ──────────────────────────────────────────
                  _SectionLabel('Surge Fee'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Switch(
                        value: _surgeFeeEnabled,
                        onChanged: (v) =>
                            setState(() => _surgeFeeEnabled = v),
                        activeTrackColor: AppColors.primary,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _surgeFeeEnabled ? 'Enabled' : 'Disabled',
                        style: TextStyle(
                          fontSize: 13,
                          color: _surgeFeeEnabled
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (_surgeFeeEnabled) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            value: _surgeFeeType,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'percentage',
                                  child: Text('Percentage')),
                              DropdownMenuItem(
                                  value: 'fixed', child: Text('Fixed (₹)')),
                            ],
                            onChanged: (v) =>
                                setState(() => _surgeFeeType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _NumField(
                            controller: _surgeValueCtrl,
                            label: 'Surge Value',
                            suffix: _surgeFeeType == 'percentage' ? '%' : '₹',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Service Charge ────────────────────────────────────
                  _SectionLabel('Additional Service Charge'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Switch(
                        value: _serviceChargeEnabled,
                        onChanged: (v) =>
                            setState(() => _serviceChargeEnabled = v),
                        activeTrackColor: AppColors.primary,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _serviceChargeEnabled ? 'Enabled' : 'Disabled',
                        style: TextStyle(
                          fontSize: 13,
                          color: _serviceChargeEnabled
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (_serviceChargeEnabled) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            value: _serviceChargeType,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'fixed', child: Text('Fixed (₹)')),
                              DropdownMenuItem(
                                  value: 'percentage',
                                  child: Text('Percentage')),
                            ],
                            onChanged: (v) =>
                                setState(() => _serviceChargeType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _NumField(
                            controller: _serviceChargeValueCtrl,
                            label: 'Charge Value',
                            suffix: _serviceChargeType == 'percentage'
                                ? '%'
                                : '₹',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Feedback + Save ───────────────────────────────────
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 15, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.error)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_success != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 15, color: AppColors.success),
                          const SizedBox(width: 8),
                          Text(_success!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.success)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded, size: 16),
                      label: const Text('Save Configuration'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      );
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  const _NumField(
      {required this.controller,
      required this.label,
      required this.suffix});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}

// ── Shared position controls ──────────────────────────────────────────────────

class _PositionControls extends StatelessWidget {
  const _PositionControls({
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
        _Arrow(
          icon: Icons.keyboard_arrow_up_rounded,
          tooltip: 'Move up',
          onTap: onMoveUp,
        ),
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
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dlg).pop(true),
                      child: const Text('Move'),
                    ),
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
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        ),
        const SizedBox(width: 2),
        _Arrow(
          icon: Icons.keyboard_arrow_down_rounded,
          tooltip: 'Move down',
          onTap: onMoveDown,
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, this.onTap});
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
          child: Icon(
            icon,
            size: 18,
            color: onTap != null ? AppColors.textSecondary : AppColors.border,
          ),
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final InstaHelpDuration duration;
  const _DiscountBadge({required this.duration});

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
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            color: AppColors.error,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Activities section ────────────────────────────────────────────────────────

class _ActivitiesSection extends ConsumerWidget {
  final String modeId;
  const _ActivitiesSection({required this.modeId});

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

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, InstaHelpActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Activity'),
        content: Text('Delete "${activity.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Delete failed: $e'),
                backgroundColor: AppColors.error),
          );
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
    final activitiesAsync =
        ref.watch(instaHelpActivitiesProvider(modeId));

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
                const Text(
                  'Activity Groups',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
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
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (activities) {
              if (activities.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No activity groups yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length,
                separatorBuilder: (context, _) =>
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
                              Text(
                                a.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
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
                                _itemList(a.includedItems, AppColors.success),
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
                                _itemList(a.excludedItems, AppColors.error),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (activities.length > 1)
                          _PositionControls(
                            position: i,
                            total: activities.length,
                            onMoveUp: i > 0
                                ? () {
                                    final reordered = [...activities]
                                      ..removeAt(i)
                                      ..insert(i - 1, a);
                                    ref
                                        .read(instaHelpActivitiesProvider(modeId).notifier)
                                        .reorder(reordered);
                                  }
                                : null,
                            onMoveDown: i < activities.length - 1
                                ? () {
                                    final reordered = [...activities]
                                      ..removeAt(i)
                                      ..insert(i + 1, a);
                                    ref
                                        .read(instaHelpActivitiesProvider(modeId).notifier)
                                        .reorder(reordered);
                                  }
                                : null,
                            onMoveTo: (target) {
                              final reordered = [...activities]
                                ..removeAt(i)
                                ..insert(target, a);
                              ref
                                  .read(instaHelpActivitiesProvider(modeId).notifier)
                                  .reorder(reordered);
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
