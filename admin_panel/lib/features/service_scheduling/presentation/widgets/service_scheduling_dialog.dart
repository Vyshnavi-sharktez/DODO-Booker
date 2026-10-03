import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/service_scheduling_repository.dart';
import '../../../global_scheduling/data/global_scheduling_repository.dart';

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

  // True when the global scheduling master switch is ON.
  bool _globalEnabled = false;

  late bool _isEnabled;
  late bool _useGlobalSchedule;
  late List<bool> _days; // index 0=Sun … 6=Sat
  late TextEditingController _maxBookings;

  // Slot generator inputs
  String? _startTime;
  String? _endTime;
  late TextEditingController _intervalHours;
  late TextEditingController _intervalMinutes;

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _maxBookings = TextEditingController();
    _intervalHours = TextEditingController();
    _intervalMinutes = TextEditingController();
    _intervalHours.addListener(() => setState(() {}));
    _intervalMinutes.addListener(() => setState(() {}));
    _loadConfig();
  }

  @override
  void dispose() {
    _maxBookings.dispose();
    _intervalHours.dispose();
    _intervalMinutes.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final serviceFuture = _repo.fetchForService(widget.serviceId);
      final globalFuture =
          GlobalSchedulingRepository(Supabase.instance.client).fetch();

      final cfg = (await serviceFuture) ??
          ServiceSchedulingConfig.defaults(widget.serviceId);
      final globalCfg = await globalFuture;

      _applyConfig(cfg);
      _globalEnabled = globalCfg.isEnabled;
    } catch (e) {
      _applyConfig(ServiceSchedulingConfig.defaults(widget.serviceId));
      if (mounted) setState(() => _error = 'Could not load existing config: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyConfig(ServiceSchedulingConfig cfg) {
    _isEnabled = cfg.isEnabled;
    _useGlobalSchedule = cfg.useGlobalSchedule;
    _days = List.generate(7, (i) => cfg.workingDays.contains(i));
    _maxBookings.text = cfg.maxBookingsPerSlot.toString();
    _startTime = cfg.slotStartTime;
    _endTime = cfg.slotEndTime;
    _intervalHours.text = cfg.slotIntervalHours.toString();
    _intervalMinutes.text = cfg.slotIntervalMinutes.toString();
  }

  // ── Time helpers ──────────────────────────────────────────────────────────────

  // "09:00 AM" → minutes since midnight
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

  // minutes since midnight → "09:00 AM"
  String _minutesToLabel(int totalMinutes) {
    final hour24 = totalMinutes ~/ 60;
    final minute = totalMinutes % 60;
    final isPm = hour24 >= 12;
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ${isPm ? 'PM' : 'AM'}';
  }

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

  // ── Slot generation ───────────────────────────────────────────────────────────

  List<String> get _generatedSlots {
    if (_startTime == null || _endTime == null) return [];
    final iH = int.tryParse(_intervalHours.text.trim()) ?? 0;
    final iM = int.tryParse(_intervalMinutes.text.trim()) ?? 0;
    return _generateSlots(_startTime!, _endTime!, iH, iM);
  }

  List<String> _generateSlots(
    String start,
    String end,
    int hours,
    int minutes,
  ) {
    final startMin = _toMinutes(start);
    final endMin = _toMinutes(end);
    final interval = hours * 60 + minutes;
    if (interval <= 0 || startMin >= endMin) return [];
    final slots = <String>[];
    var current = startMin;
    while (current < endMin) {
      slots.add(_minutesToLabel(current));
      current += interval;
    }
    return slots;
  }

  // ── Time picker ───────────────────────────────────────────────────────────────

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startTime : _endTime;
    final initial =
        current != null ? _parseLabel(current) : TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Select start time' : 'Select end time',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final label = _formatTimeOfDay(picked);
      if (isStart) {
        _startTime = label;
      } else {
        _endTime = label;
      }
      _error = null;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_useGlobalSchedule) {
      if (!_days.contains(true)) {
        setState(() => _error = 'Select at least one working day.');
        return;
      }
      if (_startTime == null || _endTime == null) {
        setState(() => _error = 'Set a start time and end time.');
        return;
      }
      final iH = int.tryParse(_intervalHours.text.trim()) ?? 0;
      final iM = int.tryParse(_intervalMinutes.text.trim()) ?? 0;
      if (iH * 60 + iM <= 0) {
        setState(() => _error = 'Interval must be at least 1 minute.');
        return;
      }
      if (_generatedSlots.isEmpty) {
        setState(
            () => _error = 'End time must be after start time to generate slots.');
        return;
      }
    }
    final maxVal = int.tryParse(_maxBookings.text.trim());
    if (!_useGlobalSchedule && (maxVal == null || maxVal < 1)) {
      setState(() => _error = 'Max bookings per slot must be at least 1.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final iH = int.tryParse(_intervalHours.text.trim()) ?? 0;
      final iM = int.tryParse(_intervalMinutes.text.trim()) ?? 0;
      final generatedSlots = (_startTime != null && _endTime != null)
          ? _generateSlots(_startTime!, _endTime!, iH, iM)
          : <String>[];

      await _repo.upsert(ServiceSchedulingConfig(
        serviceId: widget.serviceId,
        isEnabled: _isEnabled,
        useGlobalSchedule: _useGlobalSchedule,
        workingDays: [for (int i = 0; i < 7; i++) if (_days[i]) i],
        maxBookingsPerSlot: maxVal ?? 5,
        slots: generatedSlots,
        slotStartTime: _startTime,
        slotEndTime: _endTime,
        slotIntervalHours: iH,
        slotIntervalMinutes: iM,
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
          // ── Global master active banner ────────────────────────────────────
          if (_globalEnabled) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.public_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Global Scheduling is active — all services are using '
                      'the global schedule. Configure it in Global Schedule '
                      'settings. You can still save a custom schedule below '
                      'for when global scheduling is turned off.',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Enable scheduling toggle ───────────────────────────────────────
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
          const SizedBox(height: 12),

          // ── Use Global Schedule toggle (hidden when global master is ON) ───
          if (!_globalEnabled) ...[
            _SectionCard(
              child: Row(
                children: [
                  Icon(
                    Icons.public_rounded,
                    color: _useGlobalSchedule
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Use Global Schedule',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Uses the admin-wide schedule; custom slots are ignored.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _useGlobalSchedule,
                    onChanged: (v) => setState(() {
                      _useGlobalSchedule = v;
                      _error = null;
                    }),
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
            ),

            if (_useGlobalSchedule) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.primary, size: 15),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Custom slots below are saved but ignored while '
                        '"Use Global Schedule" is on.',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),

          // ── Custom schedule fields ─────────────────────────────────────────
          AnimatedOpacity(
            opacity: (!_globalEnabled && _useGlobalSchedule) ? 0.4 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_globalEnabled && _useGlobalSchedule,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Working Days
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

                  // Max Bookings per Slot
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

                  // Slot Generator
                  const _SectionLabel('Slot Generator'),
                  const SizedBox(height: 8),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TimeRow(
                          label: 'Start Time',
                          value: _startTime,
                          onTap: () => _pickTime(isStart: true),
                        ),
                        const Divider(height: 20, color: AppColors.border),
                        _TimeRow(
                          label: 'End Time',
                          value: _endTime,
                          onTap: () => _pickTime(isStart: false),
                        ),
                        const Divider(height: 20, color: AppColors.border),
                        Row(
                          children: [
                            const Text(
                              'Interval',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _intervalHours,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  hintText: '0',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'hr',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _intervalMinutes,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  hintText: '30',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'min',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Generated slots preview
                  const _SectionLabel('Generated Slots'),
                  const SizedBox(height: 8),
                  _SlotPreviewCard(slots: _generatedSlots),
                ],
              ),
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

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              value ?? 'Tap to set',
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    value != null ? FontWeight.w600 : FontWeight.normal,
                color: value != null
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.access_time_rounded,
                size: 15, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SlotPreviewCard extends StatelessWidget {
  const _SlotPreviewCard({required this.slots});
  final List<String> slots;

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
      child: slots.isEmpty
          ? Text(
              'Configure start time, end time, and interval above to preview slots.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${slots.length} slot${slots.length == 1 ? '' : 's'} will be generated',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: slots
                      .map((s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ))
                      .toList(),
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
