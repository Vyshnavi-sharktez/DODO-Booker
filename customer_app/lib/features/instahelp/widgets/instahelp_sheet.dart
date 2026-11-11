import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/instahelp_duration_model.dart';
import '../models/instahelp_activity_model.dart';
import '../models/instahelp_slot_model.dart';
import '../providers/instahelp_providers.dart';
import 'instahelp_checkout_modal.dart';

class InstaHelpSheet {
  static Future<void> show(
    BuildContext context, {
    int initialTab = 0,
    required String vendorId,
    String? assignedVendorId,
  }) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    if (isMobile) {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          final sz = MediaQuery.sizeOf(sheetCtx);
          final h = (sz.height * 0.92).clamp(400.0, sz.height * 0.96);
          return SizedBox(
            height: h,
            width: sz.width,
            child: InstaHelpContent(
              initialTab: initialTab,
              vendorId: vendorId,
              assignedVendorId: assignedVendorId,
            ),
          );
        },
      );
    } else {
      return showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (ctx) {
          final sz = MediaQuery.sizeOf(ctx);
          final w = (sz.width - 40).clamp(280.0, 520.0);
          final h = (sz.height - 80).clamp(400.0, 720.0);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            elevation: 0,
            child: SizedBox(
              width: w,
              height: h,
              child: InstaHelpContent(
                initialTab: initialTab,
                vendorId: vendorId,
                assignedVendorId: assignedVendorId,
              ),
            ),
          );
        },
      );
    }
  }
}

// ── Sheet container (also used inline on vendor detail page) ─────────────────

class InstaHelpContent extends ConsumerStatefulWidget {
  final int initialTab;
  final String vendorId;
  final String? assignedVendorId;
  final VoidCallback? onClose;

  const InstaHelpContent({
    super.key,
    this.initialTab = 0,
    required this.vendorId,
    this.assignedVendorId,
    this.onClose,
  });

  @override
  ConsumerState<InstaHelpContent> createState() => _InstaHelpContentState();
}

class _InstaHelpContentState extends ConsumerState<InstaHelpContent>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modeIdsAsync = ref.watch(instaHelpVendorModeIdsProvider(widget.vendorId));
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    final Widget body = modeIdsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 36),
              const SizedBox(height: 8),
              const Text(
                'Could not load InstaHelp options',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(
                    instaHelpVendorModeIdsProvider(widget.vendorId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (modeIds) {
        final scheduledId = modeIds['scheduled'];
        final instantId = modeIds['instant'];
        final carWashId = modeIds['car_wash'];
        if (scheduledId == null && instantId == null && carWashId == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('InstaHelp not configured yet.'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF5EFE6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tab,
                labelStyle: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w500),
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                mouseCursor: SystemMouseCursors.click,
                tabs: const [
                  Tab(height: 36, text: 'Scheduled'),
                  Tab(height: 36, text: 'Instant'),
                  Tab(height: 36, text: 'Car Wash'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  if (scheduledId != null)
                    _ScheduledContent(
                        modeId: scheduledId,
                        assignedVendorId: widget.assignedVendorId)
                  else
                    const Center(child: Text('Not available')),
                  if (instantId != null)
                    _InstantContent(
                        modeId: instantId,
                        assignedVendorId: widget.assignedVendorId)
                  else
                    const Center(child: Text('Not available')),
                  if (carWashId != null)
                    _InstantContent(
                        modeId: carWashId,
                        assignedVendorId: widget.assignedVendorId)
                  else
                    const Center(child: Text('Not available')),
                ],
              ),
            ),
          ],
        );
      },
    );

    final borderRadius = isMobile
        ? const BorderRadius.vertical(top: Radius.circular(24))
        : BorderRadius.circular(20);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: borderRadius,
          boxShadow: isMobile
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isMobile)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 2),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

              // Header
              Padding(
                padding:
                    EdgeInsets.fromLTRB(20, isMobile ? 10 : 16, 12, 12),
                child: Row(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          final router = GoRouter.of(context);
                          Navigator.of(context).pop();
                          router.go('/');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.flash_on_rounded,
                                  color: AppColors.gold, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'InstaHelp',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  'Pick a mode and duration to get started',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary, size: 20),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scheduled content (sequential: date → duration → slots) ──────────────────

class _ScheduledContent extends ConsumerStatefulWidget {
  final String modeId;
  final String? assignedVendorId;
  const _ScheduledContent({required this.modeId, this.assignedVendorId});

  @override
  ConsumerState<_ScheduledContent> createState() => _ScheduledContentState();
}

class _ScheduledContentState extends ConsumerState<_ScheduledContent> {
  DateTime? _selectedDate;
  InstaHelpDurationModel? _selectedDuration;
  InstaHelpSlotModel? _selectedSlot;

  bool get _canContinue =>
      _selectedDate != null &&
      _selectedDuration != null;

  void _onDateSelected(DateTime d) {
    if (_selectedDate?.day != d.day ||
        _selectedDate?.month != d.month ||
        _selectedDate?.year != d.year) {
      setState(() {
        _selectedDate = d;
        _selectedDuration = null;
        _selectedSlot = null;
      });
    }
  }

  void _onDurationSelected(InstaHelpDurationModel d) {
    setState(() {
      _selectedDuration = d;
      _selectedSlot = null;
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) _onDateSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final durationsAsync =
        ref.watch(instaHelpDurationsProvider(widget.modeId));
    final activitiesAsync =
        ref.watch(instaHelpActivitiesProvider(widget.modeId));

    final dateIso = _selectedDate?.toIso8601String().substring(0, 10);
    final dateAvailAsync = dateIso != null
        ? ref.watch(instaHelpDateAvailabilityProvider(
            (modeId: widget.modeId, dateIso: dateIso)))
        : null;
    final dateAvailResult = dateAvailAsync?.valueOrNull;
    final dateAvailable = dateAvailResult?.isAvailable ?? true;
    final dateUnavailableMessage = dateAvailResult?.message;

    final slotsKey = _selectedDate != null && _selectedDuration != null && dateAvailable
        ? (
            modeId: widget.modeId,
            durationId: _selectedDuration!.id,
            dateIso: dateIso!,
          )
        : null;
    final slotsAsync =
        slotsKey != null ? ref.watch(instaHelpSlotsProvider(slotsKey)) : null;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;

      return SizedBox(
        width: w,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Mode chip ─────────────────────────────────────────
                    _ModeChip(
                        icon: Icons.schedule_rounded,
                        label: 'Pick your preferred date & time',
                        color: const Color(0xFF4F6DFF)),
                    const SizedBox(height: 16),

                    // ── Step 1: Date selection ─────────────────────────────
                    _StepHeader(
                      number: 1,
                      title: 'Select Date',
                      isDone: _selectedDate != null,
                    ),
                    const SizedBox(height: 10),
                    _DateChips(
                      selected: _selectedDate,
                      onSelected: _onDateSelected,
                      onPickCustom: _pickCustomDate,
                    ),
                    const SizedBox(height: 20),

                    // ── Step 2: Duration selection (shown after date) ───────
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _selectedDate != null ? 1.0 : 0.35,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StepHeader(
                            number: 2,
                            title: 'Select Duration',
                            isDone: _selectedDuration != null,
                            locked: _selectedDate == null,
                          ),
                          const SizedBox(height: 10),
                          if (_selectedDate == null)
                            _LockedHint('Select a date first')
                          else if (dateAvailAsync != null && dateAvailAsync.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          else if (!dateAvailable)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDEDED),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.event_busy_rounded, color: AppColors.error, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      dateUnavailableMessage != null && dateUnavailableMessage.isNotEmpty
                                          ? dateUnavailableMessage
                                          : 'Not available on this date',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            durationsAsync.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                              error: (e, _) => Text('Error: $e',
                                  style: const TextStyle(
                                      color: AppColors.error, fontSize: 12)),
                              data: (durations) {
                                if (durations.isEmpty) {
                                  return const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 16),
                                    child: Text(
                                      'No duration options configured yet.',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13),
                                    ),
                                  );
                                }
                                return _DurationGrid(
                                  durations: durations,
                                  selected: _selectedDuration,
                                  onSelect: _onDurationSelected,
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Step 3: Time slot (shown after duration) ────────────
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _selectedDuration != null ? 1.0 : 0.35,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StepHeader(
                            number: 3,
                            title: 'Select Time Slot',
                            isDone: _selectedSlot != null,
                            locked: _selectedDuration == null,
                          ),
                          const SizedBox(height: 10),
                          if (_selectedDuration == null)
                            _LockedHint('Select a duration first')
                          else if (slotsAsync == null)
                            const SizedBox.shrink()
                          else
                            slotsAsync.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                              error: (e, _) => Text('Error: $e',
                                  style: const TextStyle(
                                      color: AppColors.error, fontSize: 12)),
                              data: (slots) {
                                if (slots.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.event_busy_rounded,
                                            color: AppColors.textHint,
                                            size: 20),
                                        const SizedBox(width: 10),
                                        Text(
                                          'No slots available on this date.',
                                          style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                final now = DateTime.now();
                                final isToday = _selectedDate != null &&
                                    _selectedDate!.year == now.year &&
                                    _selectedDate!.month == now.month &&
                                    _selectedDate!.day == now.day;
                                return _SlotPicker(
                                  slots: slots,
                                  selected: _selectedSlot,
                                  onSelect: (s) =>
                                      setState(() => _selectedSlot = s),
                                  isToday: isToday,
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Activity Guide ────────────────────────────────────
                    _ActivityGroupsAccordion(activitiesAsync: activitiesAsync),
                  ],
                ),
              ),
            ),

            // ── Bottom action bar ─────────────────────────────────────────
            _BottomBar(
              duration: _selectedDuration,
              selectedDate: _selectedDate,
              selectedSlot: _selectedSlot,
              enabled: _canContinue,
              modeId: widget.modeId,
              modeType: 'scheduled',
              assignedVendorId: widget.assignedVendorId,
            ),
          ],
        ),
      );
    });
  }
}

// ── Instant content ───────────────────────────────────────────────────────────

class _InstantContent extends ConsumerStatefulWidget {
  final String modeId;
  final String? assignedVendorId;
  const _InstantContent({required this.modeId, this.assignedVendorId});

  @override
  ConsumerState<_InstantContent> createState() => _InstantContentState();
}

class _InstantContentState extends ConsumerState<_InstantContent> {
  InstaHelpDurationModel? _selected;

  @override
  Widget build(BuildContext context) {
    final availAsync =
        ref.watch(instaHelpInstantAvailabilityProvider(widget.modeId));
    final durationsAsync =
        ref.watch(instaHelpDurationsProvider(widget.modeId));
    final activitiesAsync =
        ref.watch(instaHelpActivitiesProvider(widget.modeId));

    final isAvailable = availAsync.valueOrNull?.isAvailable ?? false;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;

      return SizedBox(
        width: w,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Mode chip ─────────────────────────────────────────
                    _ModeChip(
                      icon: Icons.flash_on_rounded,
                      label: 'Assigned immediately on booking',
                      color: AppColors.goldDeep,
                    ),
                    const SizedBox(height: 14),

                    // ── Availability indicator ─────────────────────────────
                    availAsync.when(
                      loading: () => _AvailabilityBanner(
                          isChecking: true,
                          isAvailable: false,
                          opensInMinutes: null),
                      error: (_, _) => _AvailabilityBanner(
                          isChecking: false,
                          isAvailable: false,
                          opensInMinutes: null),
                      data: (a) => _AvailabilityBanner(
                        isChecking: false,
                        isAvailable: a.isAvailable,
                        opensInMinutes: a.opensInMinutes,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Duration picker ───────────────────────────────────
                    Text(
                      'Select Duration',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    durationsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Text('Error: $e',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 12)),
                      data: (durations) {
                        if (durations.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No duration options configured yet.',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          );
                        }
                        return _DurationGrid(
                          durations: durations,
                          selected: _selected,
                          onSelect: (d) => setState(() => _selected = d),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // ── Activity Guide ────────────────────────────────────
                    _ActivityGroupsAccordion(activitiesAsync: activitiesAsync),
                  ],
                ),
              ),
            ),

            _BottomBar(
              duration: _selected,
              selectedDate: null,
              selectedSlot: null,
              enabled: _selected != null && isAvailable,
              modeId: widget.modeId,
              modeType: 'instant',
              unavailableHint: !isAvailable && _selected != null
                  ? 'Service unavailable right now'
                  : null,
              assignedVendorId: widget.assignedVendorId,
            ),
          ],
        ),
      );
    });
  }
}

// ── Date chips ────────────────────────────────────────────────────────────────

class _DateChips extends StatelessWidget {
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onPickCustom;

  const _DateChips({
    required this.selected,
    required this.onSelected,
    required this.onPickCustom,
  });

  static final _dayFmt = DateFormat('d MMM');

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (d.year == tomorrow.year &&
        d.month == tomorrow.month &&
        d.day == tomorrow.day) {
      return 'Tomorrow';
    }
    return _dayFmt.format(d);
  }

  static bool _isSame(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final quickDates = [
      now,
      now.add(const Duration(days: 1)),
    ];

    final isCustom = selected != null &&
        !quickDates.any((d) => _isSame(selected, d));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...quickDates.map((d) {
          final sel = _isSame(selected, d);
          return _DateChip(
            label: _dayLabel(d),
            subLabel: d.day == now.day ? null : _dayFmt.format(d),
            selected: sel,
            onTap: () => onSelected(d),
          );
        }),
        // Custom date chip
        _DateChip(
          label: isCustom ? _dayFmt.format(selected!) : 'More dates',
          icon: Icons.calendar_today_rounded,
          selected: isCustom,
          onTap: onPickCustom,
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String? subLabel;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    this.subLabel,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13,
                  color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            if (subLabel != null) ...[
              const SizedBox(width: 4),
              Text(
                subLabel!,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppColors.textHint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Slot picker with Morning/Afternoon/Evening tabs ───────────────────────────

class _SlotPicker extends StatefulWidget {
  final List<InstaHelpSlotModel> slots;
  final InstaHelpSlotModel? selected;
  final ValueChanged<InstaHelpSlotModel> onSelect;
  final bool isToday;

  const _SlotPicker({
    required this.slots,
    required this.selected,
    required this.onSelect,
    this.isToday = false,
  });

  @override
  State<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<_SlotPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _periods = ['Morning', 'Afternoon', 'Evening'];

  static String _period(String slotTime) {
    final parts = slotTime.split(' ');
    final hm = parts[0].split(':');
    int hour = int.parse(hm[0]);
    final ampm = parts[1];
    if (ampm == 'PM' && hour != 12) hour += 12;
    if (ampm == 'AM' && hour == 12) hour = 0;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  // Returns true if this slot's time is already past (with a 30-min buffer).
  static bool _isPast(String slotTime) {
    final now = DateTime.now();
    final parts = slotTime.split(' ');
    final hm = parts[0].split(':');
    int hour = int.parse(hm[0]);
    final min = int.parse(hm[1]);
    final ampm = parts[1];
    if (ampm == 'PM' && hour != 12) hour += 12;
    if (ampm == 'AM' && hour == 12) hour = 0;
    final slotMinutes = hour * 60 + min;
    final nowMinutes = now.hour * 60 + now.minute + 30; // 30-min booking buffer
    return slotMinutes <= nowMinutes;
  }

  List<InstaHelpSlotModel> _forPeriod(String period) {
    return widget.slots
        .where((s) => _period(s.slotTime) == period)
        .where((s) => !widget.isToday || !_isPast(s.slotTime))
        .toList();
  }

  List<InstaHelpSlotModel> get _morning => _forPeriod('Morning');
  List<InstaHelpSlotModel> get _afternoon => _forPeriod('Afternoon');
  List<InstaHelpSlotModel> get _evening => _forPeriod('Evening');

  int _initialTab() {
    if (_morning.isNotEmpty) return 0;
    if (_afternoon.isNotEmpty) return 1;
    return 2;
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: _initialTab());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final periodSlots = [_morning, _afternoon, _evening];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab bar for periods
        Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 1)),
          ),
          child: TabBar(
            controller: _tab,
            labelStyle: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            tabs: List.generate(
              3,
              (i) {
                final count = periodSlots[i]
                    .where((s) => s.isAvailable)
                    .length;
                return Tab(
                  height: 36,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_periods[i]),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Slot chips for the active period
        SizedBox(
          height: 44 * ((periodSlots.isNotEmpty ? 1 : 0) + 2).toDouble(),
          child: TabBarView(
            controller: _tab,
            children: List.generate(3, (i) {
              final slots = periodSlots[i];
              if (slots.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No slots in the ${_periods[i].toLowerCase()}.',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textHint),
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: slots.map((slot) {
                  final isSel = widget.selected?.slotTime == slot.slotTime;
                  final unavail = !slot.isAvailable;
                  return GestureDetector(
                    onTap: unavail ? null : () => widget.onSelect(slot),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: unavail
                            ? AppColors.surfaceVariant
                            : isSel
                                ? AppColors.primary
                                : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: unavail
                              ? AppColors.border.withValues(alpha: 0.5)
                              : isSel
                                  ? AppColors.primary
                                  : AppColors.border,
                        ),
                      ),
                      child: unavail
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slot.slotTime,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textHint,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.textHint,
                                  ),
                                ),
                                Text(
                                  'Sold Out',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              slot.slotTime,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isSel
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                    ),
                  );
                }).toList(),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── Availability banner (Instant) ─────────────────────────────────────────────

class _AvailabilityBanner extends StatelessWidget {
  final bool isChecking;
  final bool isAvailable;
  final int? opensInMinutes;

  const _AvailabilityBanner({
    required this.isChecking,
    required this.isAvailable,
    required this.opensInMinutes,
  });

  @override
  Widget build(BuildContext context) {
    if (isChecking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Checking availability...',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final color = isAvailable ? AppColors.success : AppColors.error;
    final bgColor = isAvailable
        ? const Color(0xFFEDF7EE)
        : const Color(0xFFFDEDED);
    final icon =
        isAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded;

    String message;
    if (isAvailable) {
      message = 'Available now — book instantly!';
    } else if (opensInMinutes != null) {
      final h = opensInMinutes! ~/ 60;
      final m = opensInMinutes! % 60;
      final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
      message = 'Opens in $timeStr';
    } else {
      message = 'Unavailable today';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(message,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Duration grid ─────────────────────────────────────────────────────────────

class _DurationGrid extends StatelessWidget {
  final List<InstaHelpDurationModel> durations;
  final InstaHelpDurationModel? selected;
  final ValueChanged<InstaHelpDurationModel> onSelect;

  const _DurationGrid({
    required this.durations,
    required this.selected,
    required this.onSelect,
  });

  static const _spacing = 10.0;
  static const _minCardWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final cols = ((available + _spacing) / (_minCardWidth + _spacing))
            .floor()
            .clamp(2, 4);
        final cardWidth = (available - _spacing * (cols - 1)) / cols;

        final rows = <Widget>[];
        for (int i = 0; i < durations.length; i += cols) {
          if (i > 0) rows.add(const SizedBox(height: _spacing));
          final rowItems = durations.skip(i).take(cols).toList();
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: _spacing),
                  SizedBox(
                    width: cardWidth,
                    child: j < rowItems.length
                        ? _DurationCard(
                            duration: rowItems[j],
                            isSelected: selected?.id == rowItems[j].id,
                            onTap: () => onSelect(rowItems[j]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ));
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

// ── Step header ───────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final int number;
  final String title;
  final bool isDone;
  final bool locked;

  const _StepHeader({
    required this.number,
    required this.title,
    required this.isDone,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? AppColors.success
        : locked
            ? AppColors.textHint
            : AppColors.primary;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? AppColors.success : color.withValues(alpha: 0.1),
            border: Border.all(color: color, width: isDone ? 0 : 1.5),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : Text(
                    '$number',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: locked ? AppColors.textHint : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LockedHint extends StatelessWidget {
  final String text;
  const _LockedHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textHint),
      ),
    );
  }
}

// ── Mode chip ─────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Duration card ─────────────────────────────────────────────────────────────

class _DurationCard extends StatelessWidget {
  final InstaHelpDurationModel duration;
  final bool isSelected;
  final VoidCallback onTap;

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  const _DurationCard({
    required this.duration,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              duration.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (duration.hasDiscount)
              Text(
                _currency.format(duration.price),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppColors.textHint,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _currency.format(duration.finalPrice),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected ? AppColors.gold : AppColors.primary,
                    ),
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.gold : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.gold
                          : AppColors.divider,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          size: 11, color: AppColors.primary)
                      : null,
                ),
              ],
            ),
            if (duration.hasDiscount) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.gold.withValues(alpha: 0.2)
                      : AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  duration.discountType == 'percentage'
                      ? '${duration.discountValue.toInt()}% off'
                      : '₹${duration.discountAmount.toInt()} off',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.gold : AppColors.success,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Activity guide (accordion) ────────────────────────────────────────────────

class _ActivityGroupsAccordion extends StatefulWidget {
  final AsyncValue<List<InstaHelpActivityModel>> activitiesAsync;
  const _ActivityGroupsAccordion({required this.activitiesAsync});

  @override
  State<_ActivityGroupsAccordion> createState() =>
      _ActivityGroupsAccordionState();
}

class _ActivityGroupsAccordionState extends State<_ActivityGroupsAccordion> {
  final _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const _cardWidth = 220.0;
  static const _spacing = 10.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final left = pos.pixels > 0;
    final right = pos.pixels < pos.maxScrollExtent;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.layers_rounded,
                size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Activity Guide',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        widget.activitiesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Could not load activities: $e',
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(
                  'No activities configured for this mode yet.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              );
            }

            WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());

            return Stack(
              clipBehavior: Clip.none,
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < list.length; i++) ...[
                          if (i > 0) const SizedBox(width: _spacing),
                          SizedBox(
                            width: _cardWidth,
                            child: _ActivityGroupCard(activity: list[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_canScrollLeft)
                  Positioned(
                    left: -14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrowButton(
                        Icons.chevron_left,
                        () => _scrollBy(-(_cardWidth + _spacing)),
                      ),
                    ),
                  ),
                if (_canScrollRight)
                  Positioned(
                    right: -14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrowButton(
                        Icons.chevron_right,
                        () => _scrollBy(_cardWidth + _spacing),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ActivityGroupCard extends StatelessWidget {
  final InstaHelpActivityModel activity;
  const _ActivityGroupCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.home_repair_service_rounded,
                      size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    activity.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (activity.includedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ItemsSection(
                label: 'Included',
                items: activity.includedItems,
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                bgColor: const Color(0xFFEDF7EE),
              ),
            ],
            if (activity.excludedItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ItemsSection(
                label: 'Not Included',
                items: activity.excludedItems,
                icon: Icons.cancel_rounded,
                color: AppColors.error,
                bgColor: const Color(0xFFFDEDED),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemsSection extends StatelessWidget {
  final String label;
  final List<String> items;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _ItemsSection({
    required this.label,
    required this.items,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon,
                      size: 12, color: color.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Bottom action bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final InstaHelpDurationModel? duration;
  final DateTime? selectedDate;
  final InstaHelpSlotModel? selectedSlot;
  final bool enabled;
  final String modeId;
  final String modeType;
  final String? unavailableHint;
  final String? assignedVendorId;

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  const _BottomBar({
    required this.duration,
    required this.selectedDate,
    required this.selectedSlot,
    required this.enabled,
    required this.modeId,
    required this.modeType,
    this.unavailableHint,
    this.assignedVendorId,
  });

  String get _hint {
    if (unavailableHint != null) return unavailableHint!;
    if (modeType == 'scheduled') {
      if (duration == null && selectedDate == null) {
        return 'Select date & duration to continue';
      }
      if (selectedDate == null) return 'Select a date';
      if (duration == null) return 'Select a duration';
      if (selectedSlot == null) return 'Select a time slot';
    }
    if (duration == null) return 'Select a duration to continue';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + bottomInset),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: duration == null || !enabled
                ? Text(
                    _hint,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textHint),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        duration!.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                      Text(
                        _currency.format(duration!.finalPrice),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: enabled
                ? () {
                    final d = duration!;
                    final mid = modeId;
                    final mt = modeType;
                    final date = selectedDate;
                    final slot = selectedSlot?.slotTime;
                    final rootCtx = GoRouter.of(context)
                        .routerDelegate
                        .navigatorKey
                        .currentContext;
                    Navigator.of(context).pop();
                    if (rootCtx != null) {
                      InstaHelpCheckoutModal.open(
                        rootCtx,
                        modeId: mid,
                        modeType: mt,
                        duration: d,
                        preselectedDate: date,
                        preselectedSlot: slot,
                        assignedVendorId: assignedVendorId,
                      );
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              disabledForegroundColor:
                  Colors.white.withValues(alpha: 0.6),
              minimumSize: const Size(0, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: Text(
              'Book Now',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
