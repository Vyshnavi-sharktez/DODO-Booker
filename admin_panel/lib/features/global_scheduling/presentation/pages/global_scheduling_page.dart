import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/global_scheduling_repository.dart';

class GlobalSchedulingPage extends StatefulWidget {
  const GlobalSchedulingPage({super.key});

  @override
  State<GlobalSchedulingPage> createState() => _GlobalSchedulingPageState();
}

class _GlobalSchedulingPageState extends State<GlobalSchedulingPage> {
  final _repo = GlobalSchedulingRepository(Supabase.instance.client);

  bool _loading = true;
  bool _saving = false;
  String? _error;

  GlobalSchedulingConfig? _current;
  bool _isEnabled = false;
  late List<bool> _days; // index 0=Sun … 6=Sat
  late TextEditingController _maxBookings;
  late List<String> _slots;

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _days = List.filled(7, false);
    _maxBookings = TextEditingController();
    _slots = [];
    _load();
  }

  @override
  void dispose() {
    _maxBookings.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await _repo.fetch();
      _applyConfig(cfg);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load config: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyConfig(GlobalSchedulingConfig cfg) {
    _current = cfg;
    _isEnabled = cfg.isEnabled;
    _days = List.generate(7, (i) => cfg.workingDays.contains(i));
    _maxBookings.text = cfg.maxBookingsPerSlot.toString();
    _slots = List<String>.from(cfg.slots)..sort(_slotComparator);
  }

  // ── Slot helpers ─────────────────────────────────────────────────────────────

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
    final maxVal = int.tryParse(_maxBookings.text.trim());
    if (maxVal == null || maxVal < 1) {
      setState(() => _error = 'Max bookings per slot must be at least 1.');
      return;
    }
    if (_isEnabled) {
      if (!_days.contains(true)) {
        setState(() => _error = 'Select at least one working day.');
        return;
      }
      if (_slots.isEmpty) {
        setState(() => _error = 'Add at least one time slot.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = GlobalSchedulingConfig(
        id: _current?.id,
        isEnabled: _isEnabled,
        workingDays: [for (int i = 0; i < 7; i++) if (_days[i]) i],
        maxBookingsPerSlot: maxVal,
        slots: _slots,
      );
      final saved = await _repo.save(updated);
      if (mounted) {
        setState(() => _current = saved);
        _showSnack('Global schedule saved.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page header ──────────────────────────────────────────────────
              const Text(
                'Global Scheduling',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Configure the admin-wide schedule that individual services can opt in to.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // ── Info banner ──────────────────────────────────────────────────
              _InfoBanner(
                children: [
                  _BulletRow(
                    text: 'Services can opt in from their individual '
                        'scheduling dialog ("Use Global Schedule").',
                  ),
                  const SizedBox(height: 4),
                  _BulletRow(
                    text: 'Opted-in services ignore their custom slots '
                        'and use this schedule instead.',
                  ),
                  const SizedBox(height: 4),
                  _BulletRow(
                    text: 'Disabling global scheduling here hides slots '
                        'for all opted-in services immediately.',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Master enable toggle ─────────────────────────────────────────
              _Card(
                title: 'Status',
                child: Row(
                  children: [
                    Icon(
                      _isEnabled
                          ? Icons.public_rounded
                          : Icons.public_off_rounded,
                      color: _isEnabled
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEnabled
                                ? 'Global Scheduling Enabled'
                                : 'Global Scheduling Disabled',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _isEnabled
                                ? 'Opted-in services will show slots from this schedule.'
                                : 'Opted-in services will show no slots.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isEnabled,
                      onChanged: (v) => setState(() => _isEnabled = v),
                      activeColor: AppColors.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Working Days ─────────────────────────────────────────────────
              _Card(
                title: 'Working Days',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    7,
                    (i) => _DayChip(
                      label: _dayLabels[i],
                      selected: _days[i],
                      onTap: () => setState(() => _days[i] = !_days[i]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Max Bookings per Slot ────────────────────────────────────────
              _Card(
                title: 'Max Bookings per Slot',
                child: TextFormField(
                  controller: _maxBookings,
                  decoration: InputDecoration(
                    hintText: 'e.g. 5',
                    suffixText: 'bookings',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(height: 16),

              // ── Time Slots ───────────────────────────────────────────────────
              _Card(
                title: 'Time Slots',
                headerAction: TextButton.icon(
                  onPressed: _addSlot,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Slot'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                ),
                child: _slots.isEmpty
                    ? Center(
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
                      )
                    : Column(
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
                                const Divider(
                                    height: 1, color: AppColors.border),
                            ],
                          );
                        }),
                      ),
              ),

              // ── Error ────────────────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: _error!),
              ],

              const SizedBox(height: 24),

              // ── Save ─────────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColors.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save Global Schedule',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? headerAction;

  const _Card({required this.title, required this.child, this.headerAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (headerAction != null) headerAction!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final List<Widget> children;
  const _InfoBanner({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              const Text(
                'How global scheduling works',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  final String text;
  const _BulletRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      ],
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
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
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
  const _SlotRow(
      {required this.label, required this.onEdit, required this.onDelete});
  final String label;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded,
              size: 15, color: AppColors.textSecondary),
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
            child: Text(message,
                style: TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
