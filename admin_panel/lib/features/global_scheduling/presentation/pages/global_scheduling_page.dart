import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/global_scheduling_repository.dart';
import '../../data/calendar_schedule_repository.dart';
import '../../application/scheduling_providers.dart';

// ── Mutable draft state for a single calendar entry card ───────────────────────
class _CalendarEntryDraft {
  String? id;
  final DateTime date;
  String? startTime;
  String? endTime;
  bool isEnabled;
  final TextEditingController maxBookings;
  final TextEditingController intervalHours;
  final TextEditingController intervalMinutes;
  bool isSaving = false;
  String? error;

  _CalendarEntryDraft({
    this.id,
    required this.date,
    this.startTime,
    this.endTime,
    this.isEnabled = true,
    int maxBookingsValue = 5,
    int intervalHoursValue = 0,
    int intervalMinutesValue = 30,
  })  : maxBookings = TextEditingController(text: maxBookingsValue.toString()),
        intervalHours = TextEditingController(text: intervalHoursValue.toString()),
        intervalMinutes = TextEditingController(text: intervalMinutesValue.toString());

  factory _CalendarEntryDraft.fromEntry(CalendarScheduleEntry e) =>
      _CalendarEntryDraft(
        id: e.id,
        date: e.scheduleDate,
        startTime: e.slotStartTime,
        endTime: e.slotEndTime,
        isEnabled: e.isEnabled,
        maxBookingsValue: e.maxBookingsPerSlot,
        intervalHoursValue: e.slotIntervalHours,
        intervalMinutesValue: e.slotIntervalMinutes,
      );

  void dispose() {
    maxBookings.dispose();
    intervalHours.dispose();
    intervalMinutes.dispose();
  }
}

class GlobalSchedulingPage extends ConsumerStatefulWidget {
  const GlobalSchedulingPage({super.key});

  @override
  ConsumerState<GlobalSchedulingPage> createState() => _GlobalSchedulingPageState();
}

class _GlobalSchedulingPageState extends ConsumerState<GlobalSchedulingPage>
    with SingleTickerProviderStateMixin {
  final _repo = GlobalSchedulingRepository(Supabase.instance.client);
  final _calRepo = CalendarScheduleRepository(Supabase.instance.client);

  late TabController _tabController;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  GlobalSchedulingConfig? _current;
  bool _isEnabled = false;
  late List<bool> _days; // index 0=Sun … 6=Sat
  late TextEditingController _maxBookings;

  // Slot generator inputs
  String? _startTime;
  String? _endTime;
  late TextEditingController _intervalHours;
  late TextEditingController _intervalMinutes;

  // Calendar tab
  List<_CalendarEntryDraft> _calEntries = [];

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _days = List.filled(7, false);
    _maxBookings = TextEditingController();
    _intervalHours = TextEditingController();
    _intervalMinutes = TextEditingController();
    _intervalHours.addListener(() => setState(() {}));
    _intervalMinutes.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _maxBookings.dispose();
    _intervalHours.dispose();
    _intervalMinutes.dispose();
    for (final e in _calEntries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfgFuture = _repo.fetch();
      final calFuture = _calRepo.fetchGlobal();
      final cfg = await cfgFuture;
      final calEntries = await calFuture;
      _applyConfig(cfg);
      for (final e in _calEntries) {
        e.dispose();
      }
      _calEntries = calEntries.map(_CalendarEntryDraft.fromEntry).toList();
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
    _startTime = cfg.slotStartTime;
    _endTime = cfg.slotEndTime;
    _intervalHours.text = cfg.slotIntervalHours.toString();
    _intervalMinutes.text = cfg.slotIntervalMinutes.toString();
  }

  // ── Time helpers ──────────────────────────────────────────────────────────────

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

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
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

  // ── Normal schedule save ──────────────────────────────────────────────────────

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

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final iH = int.tryParse(_intervalHours.text.trim()) ?? 0;
      final iM = int.tryParse(_intervalMinutes.text.trim()) ?? 0;
      // Preserve any previously-saved slots when the slot generator is
      // unconfigured (start/end time null after e.g. a schema migration added
      // these columns with NULL defaults). Writing [] here would silently wipe
      // a valid schedule that was saved before the generator fields existed.
      final generatedSlots = (_startTime != null && _endTime != null)
          ? _generateSlots(_startTime!, _endTime!, iH, iM)
          : (_current?.slots ?? <String>[]);

      final updated = GlobalSchedulingConfig(
        id: _current?.id,
        isEnabled: _isEnabled,
        workingDays: [for (int i = 0; i < 7; i++) if (_days[i]) i],
        maxBookingsPerSlot: maxVal,
        slots: generatedSlots,
        slotStartTime: _startTime,
        slotEndTime: _endTime,
        slotIntervalHours: iH,
        slotIntervalMinutes: iM,
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

  // ── Calendar entry operations ─────────────────────────────────────────────────

  Future<void> _addCalEntry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    final dateStr = picked.toIso8601String().split('T').first;
    final exists = _calEntries.any(
        (e) => e.date.toIso8601String().split('T').first == dateStr);
    if (exists) {
      _showSnack('An override for this date already exists.', isError: true);
      return;
    }
    setState(() {
      _calEntries.add(_CalendarEntryDraft(date: picked));
      _calEntries.sort((a, b) => a.date.compareTo(b.date));
    });
  }

  Future<void> _pickTimeForEntry(
      _CalendarEntryDraft draft, {required bool isStart}) async {
    final current = isStart ? draft.startTime : draft.endTime;
    final initial = current != null ? _parseLabel(current) : TimeOfDay.now();
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
        draft.startTime = label;
      } else {
        draft.endTime = label;
      }
    });
  }

  List<String> _generateSlotsForDraft(_CalendarEntryDraft draft) {
    if (draft.startTime == null || draft.endTime == null) return [];
    final iH = int.tryParse(draft.intervalHours.text.trim()) ?? 0;
    final iM = int.tryParse(draft.intervalMinutes.text.trim()) ?? 0;
    return _generateSlots(draft.startTime!, draft.endTime!, iH, iM);
  }

  Future<void> _saveCalEntry(_CalendarEntryDraft draft) async {
    final maxVal = int.tryParse(draft.maxBookings.text.trim());
    if (maxVal == null || maxVal < 1) {
      setState(() => draft.error = 'Max bookings must be at least 1.');
      return;
    }
    final iH = int.tryParse(draft.intervalHours.text.trim()) ?? 0;
    final iM = int.tryParse(draft.intervalMinutes.text.trim()) ?? 0;
    if (draft.startTime == null || draft.endTime == null || iH * 60 + iM <= 0) {
      setState(() => draft.error = 'Set start time, end time, and interval.');
      return;
    }
    final slots = _generateSlots(draft.startTime!, draft.endTime!, iH, iM);
    if (slots.isEmpty) {
      setState(() => draft.error = 'End time must be after start time.');
      return;
    }
    setState(() {
      draft.isSaving = true;
      draft.error = null;
    });
    try {
      final entry = CalendarScheduleEntry(
        id: draft.id,
        serviceId: null,
        scheduleDate: draft.date,
        slots: slots,
        maxBookingsPerSlot: maxVal,
        isEnabled: draft.isEnabled,
        slotStartTime: draft.startTime,
        slotEndTime: draft.endTime,
        slotIntervalHours: iH,
        slotIntervalMinutes: iM,
      );
      final saved = await _calRepo.save(entry);
      if (mounted) {
        setState(() => draft.id = saved.id);
        _showSnack('Calendar entry saved.');
      }
    } catch (e) {
      if (mounted) setState(() => draft.error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => draft.isSaving = false);
    }
  }

  Future<void> _deleteCalEntry(_CalendarEntryDraft draft) async {
    if (draft.id == null) {
      draft.dispose();
      setState(() => _calEntries.remove(draft));
      return;
    }
    try {
      await _calRepo.delete(draft.id!);
      draft.dispose();
      if (mounted) setState(() => _calEntries.remove(draft));
    } catch (e) {
      if (mounted) _showSnack('Delete failed: $e', isError: true);
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
    ref.listen<int>(schedulingRefreshProvider, (_, __) {
      if (mounted) _load();
    });
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Static header (shared across tabs) ──────────────────────────────
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'Normal Schedule'),
                      Tab(text: 'Calendar Overrides'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNormalTab(),
                _buildCalendarTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Normal schedule tab ───────────────────────────────────────────────────────

  Widget _buildNormalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info banner ────────────────────────────────────────────────────
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

            // ── Master enable toggle ───────────────────────────────────────────
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
                    activeThumbColor: AppColors.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Working Days ───────────────────────────────────────────────────
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

            // ── Max Bookings per Slot ──────────────────────────────────────────
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

            // ── Slot Generator ─────────────────────────────────────────────────
            _Card(
              title: 'Slot Generator',
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
                        width: 64,
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            hintText: '0',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('hr',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 64,
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            hintText: '30',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('min',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Generated slots preview ────────────────────────────────────────
            _Card(
              title: 'Generated Slots',
              child: _generatedSlots.isEmpty
                  ? Text(
                      'Configure start time, end time, and interval above to preview slots.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_generatedSlots.length} slot${_generatedSlots.length == 1 ? '' : 's'} will be generated',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _generatedSlots
                              .map((s) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      s,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
            ),

            // ── Error ──────────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: _error!),
            ],

            const SizedBox(height: 24),

            // ── Save ───────────────────────────────────────────────────────────
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
    );
  }

  // ── Calendar overrides tab ────────────────────────────────────────────────────

  Widget _buildCalendarTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.event_note_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Calendar overrides let you define specific time slots for a '
                      'particular date, bypassing the normal weekly schedule. '
                      'A service-level override takes priority over the global override.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_calEntries.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 40, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      const Text(
                        'No calendar overrides yet.',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final draft in _calEntries) _buildCalCard(draft),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addCalEntry,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Date Override'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalCard(_CalendarEntryDraft draft) {
    final generatedSlots = _generateSlotsForDraft(draft);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + enabled toggle
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatDate(draft.date),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                draft.isEnabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                    fontSize: 12,
                    color: draft.isEnabled
                        ? AppColors.success
                        : AppColors.textSecondary),
              ),
              const SizedBox(width: 4),
              Switch(
                value: draft.isEnabled,
                onChanged: (v) => setState(() => draft.isEnabled = v),
                activeThumbColor: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Slot generator
          const Text(
            'SLOT GENERATOR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _TimeRow(
                  label: 'Start Time',
                  value: draft.startTime,
                  onTap: () => _pickTimeForEntry(draft, isStart: true),
                ),
                const Divider(height: 16, color: AppColors.border),
                _TimeRow(
                  label: 'End Time',
                  value: draft.endTime,
                  onTap: () => _pickTimeForEntry(draft, isStart: false),
                ),
                const Divider(height: 16, color: AppColors.border),
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
                      width: 64,
                      child: TextField(
                        controller: draft.intervalHours,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          hintText: '0',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('hr',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: draft.intervalMinutes,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          hintText: '30',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('min',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),

          // Generated slots preview
          if (generatedSlots.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${generatedSlots.length} slot${generatedSlots.length == 1 ? '' : 's'} will be generated',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: generatedSlots
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  AppColors.primary.withValues(alpha: 0.25)),
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
          const SizedBox(height: 12),

          // Capacity
          Row(
            children: [
              const Text(
                'Max Bookings per Slot',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const Spacer(),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: draft.maxBookings,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    hintText: '5',
                    suffixText: 'bk',
                  ),
                ),
              ),
            ],
          ),

          if (draft.error != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: draft.error!),
          ],

          const SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (draft.id != null)
                TextButton(
                  onPressed:
                      draft.isSaving ? null : () => _deleteCalEntry(draft),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.error),
                  child: const Text('Delete'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    draft.isSaving ? null : () => _saveCalEntry(draft),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                child: draft.isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save',
                        style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
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
