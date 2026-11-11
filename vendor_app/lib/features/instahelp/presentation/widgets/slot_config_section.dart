import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/instahelp_slot_config.dart';
import '../providers/instahelp_vendor_providers.dart';

class VendorSlotConfigSection extends ConsumerWidget {
  final String modeId;
  const VendorSlotConfigSection({super.key, required this.modeId});

  void _openEdit(BuildContext context, WidgetRef ref, InstaHelpSlotConfig? existing) {
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
            ref.read(vendorSlotConfigProvider(modeId).notifier).save(
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
    final configAsync = ref.watch(vendorSlotConfigProvider(modeId));
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
              const Icon(Icons.schedule_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Slot Configuration',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          configAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (config) {
              if (config == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: Text('No slot configuration. Click Configure.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14))),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Wrap(spacing: 16, runSpacing: 10, children: [
                  _Chip(icon: Icons.access_time_rounded, label: 'Hours', value: '${config.startTime} – ${config.endTime}'),
                  _Chip(icon: Icons.timer_outlined, label: 'Interval', value: '${config.slotIntervalMinutes} min'),
                  _Chip(icon: Icons.group_rounded, label: 'Max/slot', value: '${config.maxBookingsPerSlot}'),
                  _Chip(
                    icon: Icons.calendar_today_rounded,
                    label: 'Days',
                    value: config.workingDays.map((d) => InstaHelpSlotConfig.dayLabels[d]).join(', '),
                  ),
                  _Chip(
                    icon: Icons.toggle_on_rounded,
                    label: 'Status',
                    value: config.isActive ? 'Active' : 'Inactive',
                    valueColor: config.isActive ? AppColors.success : AppColors.textSecondary,
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _Chip({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary)),
        ]),
      ]),
    );
  }
}

// ── Slot config dialog ────────────────────────────────────────────────────────

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
    if (_workingDays.isEmpty) { setState(() => _error = 'Select at least one working day.'); return; }
    if (interval == null || interval <= 0) { setState(() => _error = 'Enter a valid slot interval.'); return; }
    if (max == null || max <= 0) { setState(() => _error = 'Enter a valid max bookings per slot.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(
        workingDays: _workingDays.toList()..sort(),
        startTime: _startCtrl.text.trim(),
        endTime: _endCtrl.text.trim(),
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
      title: const Text('Slot Configuration', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Working Days', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: List.generate(7, (i) {
                  final selected = _workingDays.contains(i);
                  return FilterChip(
                    label: Text(InstaHelpSlotConfig.dayLabels[i]),
                    selected: selected,
                    onSelected: (v) => setState(() { v ? _workingDays.add(i) : _workingDays.remove(i); }),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(fontSize: 12,
                        color: selected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextField(
                  controller: _startCtrl,
                  decoration: const InputDecoration(labelText: 'Start (HH:MM)', hintText: '08:00', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.datetime,
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _endCtrl,
                  decoration: const InputDecoration(labelText: 'End (HH:MM)', hintText: '20:00', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.datetime,
                )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: _intervalCtrl,
                  decoration: const InputDecoration(labelText: 'Interval (min)', hintText: '60', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _maxCtrl,
                  decoration: const InputDecoration(labelText: 'Max Bookings/Slot', hintText: '10', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                )),
              ]),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                activeThumbColor: AppColors.success,
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
