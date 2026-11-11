import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/instahelp_duration.dart';

class DurationFormDialog extends StatefulWidget {
  final InstaHelpDuration? existing;
  final bool showSlotSchedule;
  final Future<void> Function({
    required String label,
    required int durationMinutes,
    required double price,
    required String discountType,
    required double discountValue,
    required bool isActive,
    required String slotStartTime,
    required String slotEndTime,
    required int slotIntervalMinutes,
    required int maxBookingsPerSlot,
  }) onSave;

  const DurationFormDialog({
    super.key,
    this.existing,
    this.showSlotSchedule = true,
    required this.onSave,
  });

  @override
  State<DurationFormDialog> createState() => _DurationFormDialogState();
}

class _DurationFormDialogState extends State<DurationFormDialog> {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _durationValue;
  late final TextEditingController _price;
  late final TextEditingController _discountValue;
  TimeOfDay? _slotStart;
  TimeOfDay? _slotEnd;
  late final TextEditingController _slotInterval;
  late final TextEditingController _maxBookings;
  late String _durationUnit; // 'Minutes' | 'Hours'
  late String _discountType;
  late bool _isActive;
  bool _saving = false;

  // Derives (value, unit) from stored duration_minutes when editing.
  static (double, String) _reverse(int minutes) {
    if (minutes >= 60 && minutes % 30 == 0) {
      return (minutes / 60, 'Hours');
    }
    return (minutes.toDouble(), 'Minutes');
  }

  // Computes the display label from value + unit.
  static String _buildLabel(double value, String unit) {
    if (unit == 'Minutes') return '${value.toInt()} Minutes';
    final total = (value * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (m == 0) return h == 1 ? '1 Hour' : '$h Hours';
    final hPart = h == 1 ? '1 Hour' : '$h Hours';
    return '$hPart $m Minutes';
  }

  // Normalises to duration_minutes.
  static int _toMinutes(double value, String unit) {
    if (unit == 'Minutes') return value.round();
    return (value * 60).round();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final (val, unit) = _reverse(e.durationMinutes);
      _durationValue = TextEditingController(
        text: val == val.truncateToDouble()
            ? val.toInt().toString()
            : val.toString(),
      );
      _durationUnit = unit;
    } else {
      _durationValue = TextEditingController();
      _durationUnit = 'Minutes';
    }
    _price = TextEditingController(
        text: e != null ? e.price.toStringAsFixed(2) : '');
    _discountType = e?.discountType ?? 'none';
    _discountValue = TextEditingController(
        text: (e != null && e.discountValue > 0)
            ? e.discountValue.toStringAsFixed(0)
            : '');
    _isActive = e?.isActive ?? true;
    _slotStart = _parseHHMM(e?.slotStartTime ?? '08:00');
    _slotEnd   = _parseHHMM(e?.slotEndTime   ?? '20:00');
    _slotInterval = TextEditingController(
        text: (e?.slotIntervalMinutes ?? 60).toString());
    _maxBookings = TextEditingController(
        text: (e?.maxBookingsPerSlot ?? 10).toString());
  }

  // Parse "HH:MM" or "HH:MM:SS" (Supabase TIME) → TimeOfDay
  static TimeOfDay _parseHHMM(String s) {
    final parts = s.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  // Format TimeOfDay → "HH:MM" for DB
  static String _toHHMM(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isStart}) async {
    final initial = (isStart ? _slotStart : _slotEnd) ?? TimeOfDay.now();
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
    setState(() => isStart ? _slotStart = picked : _slotEnd = picked);
  }

  @override
  void dispose() {
    _durationValue.dispose();
    _price.dispose();
    _discountValue.dispose();
    _slotInterval.dispose();
    _maxBookings.dispose();
    super.dispose();
  }

  double get _previewPrice {
    final p = double.tryParse(_price.text.trim()) ?? 0;
    final dv = double.tryParse(_discountValue.text.trim()) ?? 0;
    if (_discountType == 'percentage') {
      return (p * (1 - dv / 100)).clamp(0, double.infinity);
    }
    if (_discountType == 'fixed') {
      return (p - dv).clamp(0, double.infinity);
    }
    return p;
  }

  List<String> _generateSlotPreviews() {
    final start = _slotStart;
    final end = _slotEnd;
    final interval = int.tryParse(_slotInterval.text.trim()) ?? 0;
    if (start == null || end == null || interval <= 0) return [];
    final startMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;
    if (startMins >= endMins) return [];
    final slots = <String>[];
    for (var m = startMins; m < endMins; m += interval) {
      final h = m ~/ 60;
      final min = m % 60;
      final period = h < 12 ? 'AM' : 'PM';
      final displayH = h == 0 ? 12 : h > 12 ? h - 12 : h;
      slots.add(
          '${displayH.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} $period');
    }
    return slots;
  }

  String get _labelPreview {
    final v = double.tryParse(_durationValue.text.trim());
    if (v == null || v <= 0) return '';
    return _buildLabel(v, _durationUnit);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final v = double.parse(_durationValue.text.trim());
      await widget.onSave(
        label: _buildLabel(v, _durationUnit),
        durationMinutes: _toMinutes(v, _durationUnit),
        price: double.parse(_price.text.trim()),
        discountType: _discountType,
        discountValue: double.tryParse(_discountValue.text.trim()) ?? 0,
        isActive: _isActive,
        slotStartTime: widget.showSlotSchedule && _slotStart != null ? _toHHMM(_slotStart!) : '08:00',
        slotEndTime:   widget.showSlotSchedule && _slotEnd   != null ? _toHHMM(_slotEnd!)   : '20:00',
        slotIntervalMinutes: widget.showSlotSchedule ? (int.tryParse(_slotInterval.text.trim()) ?? 60) : 60,
        maxBookingsPerSlot: int.tryParse(_maxBookings.text.trim()) ?? 10,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEdit
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Duration' : 'Add Duration',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Duration value + unit
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _durationValue,
                              decoration: const InputDecoration(
                                labelText: 'Duration *',
                                hintText: '30',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,1}')),
                              ],
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final n = double.tryParse(v.trim());
                                if (n == null || n <= 0) return 'Must be > 0';
                                if (_durationUnit == 'Minutes' &&
                                    n != n.truncateToDouble()) {
                                  return 'Minutes must be whole number';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 130,
                            child: DropdownButtonFormField<String>(
                              value: _durationUnit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Minutes',
                                  child: Text('Minutes'),
                                ),
                                DropdownMenuItem(
                                  value: 'Hours',
                                  child: Text('Hours'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _durationUnit = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      // Label preview
                      if (_labelPreview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Label: $_labelPreview',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Price
                      TextFormField(
                        controller: _price,
                        decoration: const InputDecoration(
                          labelText: 'Price (₹) *',
                          hintText: '0.00',
                          prefixText: '₹ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final p = double.tryParse(v.trim());
                          if (p == null || p < 0) return 'Enter a valid price';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Discount section
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Discount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(optional)',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ToggleButtons(
                            isSelected: [
                              _discountType == 'none',
                              _discountType == 'percentage',
                              _discountType == 'fixed',
                            ],
                            onPressed: (i) {
                              setState(() {
                                _discountType =
                                    ['none', 'percentage', 'fixed'][i];
                                if (_discountType == 'none') {
                                  _discountValue.clear();
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            selectedColor: Colors.white,
                            fillColor: AppColors.primary,
                            textStyle: const TextStyle(fontSize: 12),
                            constraints: const BoxConstraints(
                                minWidth: 44, minHeight: 40),
                            children: const [
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 10),
                                child: Text('None'),
                              ),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 10),
                                child: Text('%'),
                              ),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 10),
                                child: Text('₹'),
                              ),
                            ],
                          ),
                          if (_discountType != 'none') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _discountValue,
                                decoration: InputDecoration(
                                  labelText: _discountType == 'percentage'
                                      ? 'Discount %'
                                      : 'Discount ₹',
                                  hintText: '0',
                                  prefixText:
                                      _discountType == 'fixed' ? '₹ ' : null,
                                  suffixText:
                                      _discountType == 'percentage' ? '%' : null,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}')),
                                ],
                                onChanged: (_) => setState(() {}),
                                validator: (v) {
                                  if (_discountType == 'none') return null;
                                  final dv =
                                      double.tryParse(v?.trim() ?? '') ?? 0;
                                  if (_discountType == 'percentage' &&
                                      dv > 100) {
                                    return 'Max 100%';
                                  }
                                  final p = double.tryParse(
                                          _price.text.trim()) ??
                                      0;
                                  if (_discountType == 'fixed' && dv > p) {
                                    return 'Cannot exceed price';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ],
                      ),

                      // Final price preview
                      if (_discountType != 'none') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  size: 16, color: AppColors.success),
                              const SizedBox(width: 8),
                              Text(
                                'Final payable price: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                _currency.format(_previewPrice),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Active toggle
                      _ToggleRow(
                        label: 'Active',
                        subtitle: 'Inactive options are hidden from customers',
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),

                      if (widget.showSlotSchedule) ...[
                      const Text(
                        'Slot Schedule',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _TimePickerTile(
                              label: 'Start Time',
                              value: _slotStart,
                              onTap: () => _pickTime(isStart: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimePickerTile(
                              label: 'End Time',
                              value: _slotEnd,
                              onTap: () => _pickTime(isStart: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _slotInterval,
                        decoration: const InputDecoration(
                          labelText: 'Interval (min) *',
                          hintText: '60',
                          suffixText: 'min',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),

                      // Slot preview
                      Builder(builder: (_) {
                        final slots = _generateSlotPreviews();
                        if (slots.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              '${slots.length} slots generated',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: slots.map((s) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )).toList(),
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 12),
                      ],

                      // Max bookings — always shown
                      TextFormField(
                        controller: _maxBookings,
                        decoration: const InputDecoration(
                          labelText: 'Max Bookings *',
                          hintText: '10',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Add Duration'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;
  const _TimePickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  static String _display(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2, '0')}:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: value != null ? AppColors.primary : AppColors.border,
            width: value != null ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: value != null
              ? AppColors.primary.withValues(alpha: 0.05)
              : AppColors.background,
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded,
                size: 16,
                color: value != null ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    value != null ? _display(value!) : 'Tap to set',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value != null
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: value != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_rounded,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.visibility_rounded : Icons.visibility_off_outlined,
            color: value ? AppColors.success : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}
