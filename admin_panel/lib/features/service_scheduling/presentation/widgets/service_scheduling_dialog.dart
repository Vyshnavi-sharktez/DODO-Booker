import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/service_scheduling_repository.dart';

class ServiceSchedulingDialog extends StatefulWidget {
  final String serviceId;
  final String serviceName;

  const ServiceSchedulingDialog({
    super.key,
    required this.serviceId,
    required this.serviceName,
  });

  @override
  State<ServiceSchedulingDialog> createState() =>
      _ServiceSchedulingDialogState();
}

class _ServiceSchedulingDialogState extends State<ServiceSchedulingDialog> {
  final _repo = ServiceSchedulingRepository(Supabase.instance.client);

  bool _loading = true;
  bool _saving = false;
  String? _error;

  late bool _isEnabled;
  late List<bool> _days;       // index 0=Sun … 6=Sat
  late TextEditingController _maxBookings;
  late List<String> _slots;    // sorted "HH:MM AM/PM" labels

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _maxBookings = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _maxBookings.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await _repo.fetchForService(widget.serviceId) ??
          ServiceSchedulingConfig.defaults(widget.serviceId);
      _applyConfig(cfg);
    } catch (e) {
      _applyConfig(ServiceSchedulingConfig.defaults(widget.serviceId));
      if (mounted) setState(() => _error = 'Could not load existing config: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyConfig(ServiceSchedulingConfig cfg) {
    _isEnabled = cfg.isEnabled;
    _days = List.generate(7, (i) => cfg.workingDays.contains(i));
    _maxBookings.text = cfg.maxBookingsPerSlot.toString();
    _slots = List<String>.from(cfg.slots)..sort(_slotComparator);
  }

  // ── Slot helpers ─────────────────────────────────────────────────────────────

  // "09:00 AM" → minutes since midnight (for sorting / period detection)
  int _toMinutes(String label) {
    final parts = label.split(' ');
    final hp = parts[0].split(':');
    var hour = int.parse(hp[0]);
    final minute = int.parse(hp[1]);
    final isPm = parts[1] == 'PM';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  int _slotComparator(String a, String b) =>
      _toMinutes(a).compareTo(_toMinutes(b));

  String _formatTimeOfDay(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  TimeOfDay _parseLabel(String label) {
    final parts = label.split(' ');
    final hp = parts[0].split(':');
    var hour = int.parse(hp[0]);
    final minute = int.parse(hp[1]);
    if (parts[1] == 'PM' && hour != 12) hour += 12;
    if (parts[1] == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  // ── Slot actions ─────────────────────────────────────────────────────────────

  Future<void> _addSlot() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Add time slot',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final label = _formatTimeOfDay(picked);
    if (_slots.contains(label)) {
      setState(() => _error = '"$label" is already in the list.');
      return;
    }
    setState(() {
      _error = null;
      _slots = [..._slots, label]..sort(_slotComparator);
    });
  }

  Future<void> _editSlot(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseLabel(_slots[index]),
      helpText: 'Edit time slot',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final label = _formatTimeOfDay(picked);
    // Allow same value (no-op) or reject true duplicate with another slot
    final otherSlots = List<String>.from(_slots)..removeAt(index);
    if (otherSlots.contains(label)) {
      setState(() => _error = '"$label" is already in the list.');
      return;
    }
    setState(() {
      _error = null;
      _slots = [...otherSlots, label]..sort(_slotComparator);
    });
  }

  void _deleteSlot(int index) {
    setState(() {
      _slots = List<String>.from(_slots)..removeAt(index);
      _error = null;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_days.contains(true)) {
      setState(() => _error = 'Select at least one working day.');
      return;
    }
    if (_slots.isEmpty) {
      setState(() => _error = 'Add at least one time slot.');
      return;
    }
    final maxVal = int.tryParse(_maxBookings.text.trim());
    if (maxVal == null || maxVal < 1) {
      setState(() => _error = 'Max bookings per slot must be at least 1.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.upsert(ServiceSchedulingConfig(
        serviceId: widget.serviceId,
        isEnabled: _isEnabled,
        workingDays: [for (int i = 0; i < 7; i++) if (_days[i]) i],
        maxBookingsPerSlot: maxVal,
        slots: _slots,
      ));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scheduling saved.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(child: SingleChildScrollView(child: _buildForm())),
            if (!_loading) _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scheduling',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.serviceName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Enable toggle ──────────────────────────────────────────────────
          _SectionCard(
            child: Row(
              children: [
                Icon(
                  _isEnabled
                      ? Icons.check_circle_outline_rounded
                      : Icons.cancel_outlined,
                  color: _isEnabled
                      ? AppColors.success
                      : AppColors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Enable Scheduling',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _isEnabled,
                  onChanged: (v) => setState(() => _isEnabled = v),
                  activeThumbColor: AppColors.success,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Working Days ───────────────────────────────────────────────────
          const _SectionLabel('Working Days'),
          const SizedBox(height: 8),
          _SectionCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                return _DayChip(
                  label: _dayLabels[i],
                  selected: _days[i],
                  onTap: () => setState(() => _days[i] = !_days[i]),
                );
              }),
            ),
          ),
          const SizedBox(height: 20),

          // ── Max bookings ───────────────────────────────────────────────────
          const _SectionLabel('Max Bookings per Slot'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _maxBookings,
            decoration: const InputDecoration(
              hintText: 'e.g. 5',
              suffixText: 'bookings',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 20),

          // ── Time Slots ─────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(child: _SectionLabel('Time Slots')),
              TextButton.icon(
                onPressed: _addSlot,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Slot'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_slots.isEmpty)
            _SectionCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No slots configured yet.\nTap "Add Slot" to add a time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            )
          else
            _SectionCard(
              child: Column(
                children: List.generate(_slots.length, (i) {
                  final isLast = i == _slots.length - 1;
                  return Column(
                    children: [
                      _SlotRow(
                        label: _slots[i],
                        onEdit: () => _editSlot(i),
                        onDelete: () => _deleteSlot(i),
                      ),
                      if (!isLast)
                        const Divider(height: 1, color: AppColors.border),
                    ],
                  );
                }),
              ),
            ),

          // ── Error ──────────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Scheduling'),
          ),
        ],
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.label,
    required this.onEdit,
    required this.onDelete,
  });
  final String label;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.access_time_rounded,
            size: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 15),
            tooltip: 'Edit',
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 15),
            tooltip: 'Remove',
            color: AppColors.error,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
