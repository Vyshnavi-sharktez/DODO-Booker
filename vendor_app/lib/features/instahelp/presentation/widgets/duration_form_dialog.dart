import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/instahelp_duration.dart';

class VendorDurationFormDialog extends StatefulWidget {
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

  const VendorDurationFormDialog({
    super.key,
    this.existing,
    this.showSlotSchedule = true,
    required this.onSave,
  });

  @override
  State<VendorDurationFormDialog> createState() => _VendorDurationFormDialogState();
}

class _VendorDurationFormDialogState extends State<VendorDurationFormDialog> {
  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _durationValue;
  late final TextEditingController _price;
  late final TextEditingController _discountValue;
  late final TextEditingController _slotInterval;
  late final TextEditingController _maxBookings;
  TimeOfDay? _slotStart;
  TimeOfDay? _slotEnd;
  late String _durationUnit;
  late String _discountType;
  late bool _isActive;
  bool _saving = false;

  static (double, String) _reverse(int minutes) {
    if (minutes >= 60 && minutes % 30 == 0) return (minutes / 60, 'Hours');
    return (minutes.toDouble(), 'Minutes');
  }

  static String _buildLabel(double value, String unit) {
    if (unit == 'Minutes') return '${value.toInt()} Minutes';
    final total = (value * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (m == 0) return h == 1 ? '1 Hour' : '$h Hours';
    return '${h == 1 ? "1 Hour" : "$h Hours"} $m Minutes';
  }

  static int _toMinutes(double value, String unit) {
    return unit == 'Minutes' ? value.round() : (value * 60).round();
  }

  static TimeOfDay _parseHHMM(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _toHHMM(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final (val, unit) = _reverse(e.durationMinutes);
      _durationValue = TextEditingController(
        text: val == val.truncateToDouble() ? val.toInt().toString() : val.toString(),
      );
      _durationUnit = unit;
    } else {
      _durationValue = TextEditingController();
      _durationUnit = 'Minutes';
    }
    _price = TextEditingController(text: e != null ? e.price.toStringAsFixed(2) : '');
    _discountType = e?.discountType ?? 'none';
    _discountValue = TextEditingController(
        text: (e != null && e.discountValue > 0) ? e.discountValue.toStringAsFixed(0) : '');
    _isActive = e?.isActive ?? true;
    _slotStart = _parseHHMM(e?.slotStartTime ?? '08:00');
    _slotEnd = _parseHHMM(e?.slotEndTime ?? '20:00');
    _slotInterval = TextEditingController(text: (e?.slotIntervalMinutes ?? 60).toString());
    _maxBookings = TextEditingController(text: (e?.maxBookingsPerSlot ?? 10).toString());
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

  Future<void> _pickTime({required bool isStart}) async {
    final initial = (isStart ? _slotStart : _slotEnd) ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Select start time' : 'Select end time',
    );
    if (picked == null || !mounted) return;
    setState(() => isStart ? _slotStart = picked : _slotEnd = picked);
  }

  double get _previewPrice {
    final p = double.tryParse(_price.text.trim()) ?? 0;
    final dv = double.tryParse(_discountValue.text.trim()) ?? 0;
    if (_discountType == 'percentage') return (p * (1 - dv / 100)).clamp(0, double.infinity);
    if (_discountType == 'fixed') return (p - dv).clamp(0, double.infinity);
    return p;
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
        slotEndTime: widget.showSlotSchedule && _slotEnd != null ? _toHHMM(_slotEnd!) : '20:00',
        slotIntervalMinutes: widget.showSlotSchedule ? (int.tryParse(_slotInterval.text.trim()) ?? 60) : 60,
        maxBookingsPerSlot: int.tryParse(_maxBookings.text.trim()) ?? 10,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(isEdit ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(isEdit ? 'Edit Duration' : 'Add Duration',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _durationValue,
                              decoration: const InputDecoration(labelText: 'Duration *', hintText: '30'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}'))],
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                final n = double.tryParse(v.trim());
                                if (n == null || n <= 0) return 'Must be > 0';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 120,
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _durationUnit,
                              decoration: const InputDecoration(labelText: 'Unit'),
                              items: const [
                                DropdownMenuItem(value: 'Minutes', child: Text('Minutes')),
                                DropdownMenuItem(value: 'Hours', child: Text('Hours')),
                              ],
                              onChanged: (v) { if (v != null) setState(() => _durationUnit = v); },
                            ),
                          ),
                        ],
                      ),
                      if (_labelPreview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(children: [
                            Icon(Icons.timer_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text('Label: $_labelPreview',
                                style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _price,
                        decoration: const InputDecoration(labelText: 'Price (₹) *', prefixText: '₹ '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final p = double.tryParse(v.trim());
                          if (p == null || p < 0) return 'Enter a valid price';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Text('Discount', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('(optional)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ]),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ToggleButtons(
                            isSelected: [_discountType == 'none', _discountType == 'percentage', _discountType == 'fixed'],
                            onPressed: (i) {
                              setState(() {
                                _discountType = ['none', 'percentage', 'fixed'][i];
                                if (_discountType == 'none') _discountValue.clear();
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            selectedColor: Colors.white,
                            fillColor: AppColors.primary,
                            textStyle: const TextStyle(fontSize: 12),
                            constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
                            children: const [
                              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('None')),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('%')),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('₹')),
                            ],
                          ),
                          if (_discountType != 'none') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _discountValue,
                                decoration: InputDecoration(
                                  labelText: _discountType == 'percentage' ? 'Discount %' : 'Discount ₹',
                                  prefixText: _discountType == 'fixed' ? '₹ ' : null,
                                  suffixText: _discountType == 'percentage' ? '%' : null,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_discountType != 'none') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            Icon(Icons.check_circle_outline_rounded, size: 15, color: AppColors.success),
                            const SizedBox(width: 8),
                            Text('Final price: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Text(_currency.format(_previewPrice),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        subtitle: Text('Inactive options are hidden from customers',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: AppColors.success,
                      ),
                      if (widget.showSlotSchedule) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text('Slot Schedule',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _TimeTile(label: 'Start Time', value: _slotStart, onTap: () => _pickTime(isStart: true))),
                          const SizedBox(width: 12),
                          Expanded(child: _TimeTile(label: 'End Time', value: _slotEnd, onTap: () => _pickTime(isStart: false))),
                        ]),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _slotInterval,
                          decoration: const InputDecoration(labelText: 'Interval (min) *', suffixText: 'min'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n <= 0) return 'Must be > 0';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _maxBookings,
                        decoration: const InputDecoration(labelText: 'Max Bookings *', hintText: '10'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

class _TimeTile extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;
  const _TimeTile({required this.label, required this.value, required this.onTap});

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: value != null ? AppColors.primary : AppColors.border,
            width: value != null ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: value != null ? AppColors.primary.withValues(alpha: 0.05) : AppColors.background,
        ),
        child: Row(children: [
          Icon(Icons.access_time_rounded, size: 16,
              color: value != null ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text(value != null ? _display(value!) : 'Tap to set',
                    style: TextStyle(fontSize: 13,
                        fontWeight: value != null ? FontWeight.w700 : FontWeight.w400,
                        color: value != null ? AppColors.textPrimary : AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.edit_rounded, size: 14, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}
