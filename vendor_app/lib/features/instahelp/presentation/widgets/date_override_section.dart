import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/instahelp_date_override.dart';
import '../providers/instahelp_vendor_providers.dart';

class VendorDateOverrideSection extends ConsumerWidget {
  final String modeId;
  const VendorDateOverrideSection({super.key, required this.modeId});

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
            ref.read(vendorDateOverridesProvider(modeId).notifier).create(
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
            ref.read(vendorDateOverridesProvider(modeId).notifier).update(
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(vendorDateOverridesProvider(modeId).notifier).delete(o.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overridesAsync = ref.watch(vendorDateOverridesProvider(modeId));

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
            child: Row(
              children: [
                const Icon(Icons.event_busy_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Calendar Overrides',
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
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              child:
                  Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (overrides) {
              if (overrides.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No overrides yet. Add one to block a date or change its hours.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
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
                          onPressed: () => _confirmDelete(context, ref, o),
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
    final first = isStart
        ? DateTime.now().subtract(const Duration(days: 1))
        : _startDate;
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        startDate: _startDate,
        endDate: _endDate,
        isAvailable: _isAvailable,
        customStartTime:
            (_customHours && _isAvailable) ? _customStartCtrl.text.trim() : null,
        customEndTime:
            (_customHours && _isAvailable) ? _customEndCtrl.text.trim() : null,
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
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Date Range',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _DateButton(
                    label: 'Start',
                    date: _startDate,
                    onTap: () => _pickDate(isStart: true),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _DateButton(
                    label: 'End',
                    date: _endDate,
                    onTap: () => _pickDate(isStart: false),
                  )),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date Range is Available',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _isAvailable
                      ? 'Slots will be generated'
                      : 'No slots on these dates',
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
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  value: _customHours,
                  onChanged: (v) => setState(() => _customHours = v),
                  activeThumbColor: AppColors.primary,
                ),
                if (_customHours)
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                        controller: _customStartCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Start (HH:MM)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: TextField(
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
                  hintText: 'e.g. Closed for a holiday',
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
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: AppColors.error, fontSize: 12))),
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
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(isEdit ? 'Save Changes' : 'Add Override'),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton(
      {required this.label, required this.date, required this.onTap});
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
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(_fmt.format(date),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              )),
              const Icon(Icons.calendar_today_rounded,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      );
}
