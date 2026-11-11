import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/instahelp_providers.dart';
import '../../domain/models/instahelp_slot_config.dart';
import '../../domain/models/instahelp_date_override.dart';

class SlotConfigSection extends ConsumerWidget {
  final String modeId;
  // When false only the Date Overrides panel is rendered (used for Instant mode).
  final bool showGlobalConfig;

  const SlotConfigSection({
    super.key,
    required this.modeId,
    this.showGlobalConfig = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (showGlobalConfig) ...[
          _SlotGlobalConfig(modeId: modeId),
          const SizedBox(height: 24),
        ],
        _DateOverridesPanel(modeId: modeId),
      ],
    );
  }
}

// ── Global slot configuration ─────────────────────────────────────────────────

class _SlotGlobalConfig extends ConsumerWidget {
  final String modeId;
  const _SlotGlobalConfig({required this.modeId});

  void _openEdit(BuildContext context, WidgetRef ref,
      InstaHelpSlotConfig? existing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SlotConfigDialog(
        existing: existing,
        onSave: ({
          required workingDays,
          required startTime,
          required endTime,
          required slotIntervalMinutes,
          required maxBookingsPerSlot,
          required isActive,
        }) =>
            ref.read(instaHelpSlotConfigProvider(modeId).notifier).save(
                  workingDays: workingDays,
                  startTime: startTime,
                  endTime: endTime,
                  slotIntervalMinutes: slotIntervalMinutes,
                  maxBookingsPerSlot: maxBookingsPerSlot,
                  isActive: isActive,
                ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(instaHelpSlotConfigProvider(modeId));

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
                const Icon(Icons.schedule_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Slot Configuration',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                configAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (config) => FilledButton.icon(
                    onPressed: () => _openEdit(context, ref, config),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: Text(config == null ? 'Configure' : 'Edit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          configAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child:
                  Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (config) {
              if (config == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No slot configuration found. Click Configure.',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ),
                );
              }
              final slots = _generateSlotsFromStrings(
                  config.startTime, config.endTime, config.slotIntervalMinutes);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 20,
                      runSpacing: 12,
                      children: [
                        _InfoChip(
                          icon: Icons.access_time_rounded,
                          label: 'Hours',
                          value: '${config.startTime} – ${config.endTime}',
                        ),
                        _InfoChip(
                          icon: Icons.timer_outlined,
                          label: 'Interval',
                          value: '${config.slotIntervalMinutes} min',
                        ),
                        _InfoChip(
                          icon: Icons.group_rounded,
                          label: 'Max/slot',
                          value: '${config.maxBookingsPerSlot}',
                        ),
                        _InfoChip(
                          icon: Icons.calendar_today_rounded,
                          label: 'Working days',
                          value: config.workingDays
                              .map((d) => InstaHelpSlotConfig.dayLabels[d])
                              .join(', '),
                        ),
                        _InfoChip(
                          icon: Icons.toggle_on_rounded,
                          label: 'Status',
                          value: config.isActive ? 'Active' : 'Inactive',
                          valueColor: config.isActive
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ],
                    ),
                    if (slots.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        '${slots.length} slots per day',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: slots
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

List<String> _generateSlotsFromStrings(
    String startStr, String endStr, int intervalMinutes) {
  List<int> _parse(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return [-1, -1];
    return [int.tryParse(parts[0]) ?? -1, int.tryParse(parts[1]) ?? -1];
  }

  final s = _parse(startStr);
  final e = _parse(endStr);
  if (s[0] < 0 || e[0] < 0 || intervalMinutes <= 0) return [];
  final startMins = s[0] * 60 + s[1];
  final endMins = e[0] * 60 + e[1];
  if (startMins >= endMins) return [];
  final slots = <String>[];
  for (var m = startMins; m < endMins; m += intervalMinutes) {
    final h = m ~/ 60;
    final min = m % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final displayH = h == 0 ? 12 : h > 12 ? h - 12 : h;
    slots.add(
        '${displayH.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} $period');
  }
  return slots;
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
              Text(value,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Date overrides panel ──────────────────────────────────────────────────────

class _DateOverridesPanel extends ConsumerWidget {
  final String modeId;
  const _DateOverridesPanel({required this.modeId});

  static final _dateFmt = DateFormat('d MMM yyyy');

  void _openAdd(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DateOverrideDialog(
        onSave: ({
          required startDate,
          required endDate,
          required isAvailable,
          required customStartTime,
          required customEndTime,
          required notes,
        }) =>
            ref.read(instaHelpDateOverridesProvider(modeId).notifier).create(
                  startDate: startDate,
                  endDate: endDate,
                  isAvailable: isAvailable,
                  customStartTime: customStartTime,
                  customEndTime: customEndTime,
                  notes: notes,
                ),
      ),
    );
  }

  void _openEdit(
      BuildContext context, WidgetRef ref, InstaHelpDateOverride existing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DateOverrideDialog(
        existing: existing,
        onSave: ({
          required startDate,
          required endDate,
          required isAvailable,
          required customStartTime,
          required customEndTime,
          required notes,
        }) =>
            ref.read(instaHelpDateOverridesProvider(modeId).notifier).update(
                  existing.id,
                  startDate: startDate,
                  endDate: endDate,
                  isAvailable: isAvailable,
                  customStartTime: customStartTime,
                  customEndTime: customEndTime,
                  notes: notes,
                ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, InstaHelpDateOverride o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Override'),
        content: Text(
            'Remove override for ${o.isSingleDay ? _dateFmt.format(o.startDate) : '${_dateFmt.format(o.startDate)} – ${_dateFmt.format(o.endDate)}'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(instaHelpDateOverridesProvider(modeId).notifier)
          .delete(o.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overridesAsync =
        ref.watch(instaHelpDateOverridesProvider(modeId));

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
                const Icon(Icons.event_busy_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Date Overrides',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _openAdd(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Override'),
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
          overridesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (overrides) {
              if (overrides.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No date overrides. Add one to block a date or change its hours.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: overrides.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final o = overrides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: o.isAvailable
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.isSingleDay
                                    ? _dateFmt.format(o.startDate)
                                    : '${_dateFmt.format(o.startDate)} – ${_dateFmt.format(o.endDate)}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                              Text(
                                o.isAvailable
                                    ? (o.customStartTime != null
                                        ? 'Custom hours: ${o.customStartTime} – ${o.customEndTime}'
                                        : 'Available (default hours)')
                                    : 'Not Available',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: o.isAvailable
                                        ? AppColors.textSecondary
                                        : AppColors.error),
                              ),
                              if (o.notes != null && o.notes!.isNotEmpty)
                                Text(o.notes!,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded,
                              size: 17, color: AppColors.primary),
                          tooltip: 'Edit',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openEdit(context, ref, o),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 17, color: AppColors.error),
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _confirmDelete(context, ref, o),
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

// ── Slot config edit dialog ───────────────────────────────────────────────────

typedef _SlotConfigSaveCallback = Future<void> Function({
  required List<int> workingDays,
  required String startTime,
  required String endTime,
  required int slotIntervalMinutes,
  required int maxBookingsPerSlot,
  required bool isActive,
});

class _SlotConfigDialog extends StatefulWidget {
  final InstaHelpSlotConfig? existing;
  final _SlotConfigSaveCallback onSave;
  const _SlotConfigDialog({this.existing, required this.onSave});

  @override
  State<_SlotConfigDialog> createState() => _SlotConfigDialogState();
}

class _SlotConfigDialogState extends State<_SlotConfigDialog> {
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  late Set<int> _workingDays;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _workingDays = e != null ? Set.of(e.workingDays) : {0, 1, 2, 3, 4, 5, 6};
    _isActive = e?.isActive ?? true;
    _startCtrl.text = e?.startTime ?? '08:00';
    _endCtrl.text = e?.endTime ?? '20:00';
    _intervalCtrl.text = (e?.slotIntervalMinutes ?? 60).toString();
    _maxCtrl.text = (e?.maxBookingsPerSlot ?? 10).toString();
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    _intervalCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final interval = int.tryParse(_intervalCtrl.text.trim());
    final max = int.tryParse(_maxCtrl.text.trim());
    final start = _startCtrl.text.trim();
    final end = _endCtrl.text.trim();
    if (_workingDays.isEmpty) {
      setState(() => _error = 'Select at least one working day.');
      return;
    }
    if (interval == null || interval <= 0) {
      setState(() => _error = 'Enter a valid slot interval (minutes).');
      return;
    }
    if (max == null || max <= 0) {
      setState(() => _error = 'Enter a valid max bookings per slot.');
      return;
    }
    if (start.isEmpty || end.isEmpty) {
      setState(() => _error = 'Enter start and end times (HH:MM).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        workingDays: _workingDays.toList()..sort(),
        startTime: start,
        endTime: end,
        slotIntervalMinutes: interval,
        maxBookingsPerSlot: max,
        isActive: _isActive,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Slot Configuration',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Working Days',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: List.generate(7, (i) {
                  final selected = _workingDays.contains(i);
                  return FilterChip(
                    label: Text(InstaHelpSlotConfig.dayLabels[i]),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _workingDays.add(i);
                      } else {
                        _workingDays.remove(i);
                      }
                    }),
                    selectedColor:
                        AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Start Time (HH:MM)',
                        hintText: '08:00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'End Time (HH:MM)',
                        hintText: '20:00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _intervalCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Slot Interval (min)',
                        hintText: '60',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Max Bookings/Slot',
                        hintText: '10',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Builder(builder: (_) {
                final interval =
                    int.tryParse(_intervalCtrl.text.trim()) ?? 0;
                final slots = _generateSlotsFromStrings(
                    _startCtrl.text.trim(),
                    _endCtrl.text.trim(),
                    interval);
                if (slots.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${slots.length} slots per day',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: slots
                          .map((s) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              }),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                activeThumbColor: AppColors.success,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Date override dialog ──────────────────────────────────────────────────────

typedef _DateOverrideSaveCallback = Future<void> Function({
  required DateTime startDate,
  required DateTime endDate,
  required bool isAvailable,
  required String? customStartTime,
  required String? customEndTime,
  required String? notes,
});

class _DateOverrideDialog extends StatefulWidget {
  final InstaHelpDateOverride? existing;
  final _DateOverrideSaveCallback onSave;
  const _DateOverrideDialog({this.existing, required this.onSave});

  @override
  State<_DateOverrideDialog> createState() => _DateOverrideDialogState();
}

class _DateOverrideDialogState extends State<_DateOverrideDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isAvailable = false;
  bool _customHours = false;
  final _customStartCtrl = TextEditingController();
  final _customEndCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  static final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate ?? DateTime.now();
    _isAvailable = e?.isAvailable ?? false;
    _customHours = e?.customStartTime != null;
    _customStartCtrl.text = e?.customStartTime ?? '';
    _customEndCtrl.text = e?.customEndTime ?? '';
    _notesCtrl.text = e?.notes ?? '';
  }

  @override
  void dispose() {
    _customStartCtrl.dispose();
    _customEndCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final first = isStart ? DateTime.now().subtract(const Duration(days: 1)) : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(
        startDate: _startDate,
        endDate: _endDate,
        isAvailable: _isAvailable,
        customStartTime: (_customHours && _isAvailable) ? _customStartCtrl.text.trim() : null,
        customEndTime: (_customHours && _isAvailable) ? _customEndCtrl.text.trim() : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isEdit ? 'Edit Date Override' : 'Add Date Override',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date range
              const Text('Date Range',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _DateButton(
                    label: 'Start',
                    date: _startDate,
                    onTap: () => _pickDate(isStart: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _DateButton(
                    label: 'End',
                    date: _endDate,
                    onTap: () => _pickDate(isStart: false),
                  )),
                ],
              ),
              const SizedBox(height: 14),

              // Availability toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date Range is Available',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _isAvailable ? 'Slots will be generated' : 'No slots on these dates',
                  style: const TextStyle(fontSize: 12),
                ),
                value: _isAvailable,
                onChanged: (v) => setState(() => _isAvailable = v),
                activeThumbColor: AppColors.success,
              ),

              if (_isAvailable) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom Hours',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  value: _customHours,
                  onChanged: (v) => setState(() => _customHours = v),
                  activeThumbColor: AppColors.primary,
                ),
                if (_customHours)
                  Row(
                    children: [
                      Expanded(child: TextField(
                        controller: _customStartCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Start (HH:MM)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(
                        controller: _customEndCtrl,
                        decoration: const InputDecoration(
                          labelText: 'End (HH:MM)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      )),
                    ],
                  ),
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Customer Message (optional)',
                  hintText: 'e.g. We are closed for a holiday',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: AppColors.error, size: 15),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: TextStyle(color: AppColors.error, fontSize: 12))),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(isEdit ? 'Save Changes' : 'Add Override'),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  static final _fmt = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(_fmt.format(date), style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          )),
          const Icon(Icons.calendar_today_rounded, size: 14,
              color: AppColors.textSecondary),
        ],
      ),
    ),
  );
}
