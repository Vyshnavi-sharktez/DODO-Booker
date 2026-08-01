import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../domain/models/amc_plan.dart';

typedef _SaveFn = Future<void> Function({
  required String planName,
  required String packageDuration,
  int? packageDurationValue,
  required String serviceInterval,
  int? serviceIntervalValue,
  required double pricePerVisit,
  required String discountType,
  required double discountValue,
  required bool isActive,
});

class AmcPlanFormDialog extends StatefulWidget {
  const AmcPlanFormDialog({
    super.key,
    this.existing,
    required this.onSave,
    this.servicePrice,
  });

  final AmcPlan? existing;
  final _SaveFn onSave;

  /// When set (catalog context), the price per visit field is hidden and this
  /// value is used automatically instead. Admin only configures duration,
  /// interval, and discount.
  final double? servicePrice;

  @override
  State<AmcPlanFormDialog> createState() => _AmcPlanFormDialogState();
}

class _AmcPlanFormDialogState extends State<AmcPlanFormDialog> {
  static const _packageOptions = [
    ('monthly', 'Monthly', '30 days'),
    ('quarterly', 'Quarterly', '91 days'),
    ('half_yearly', 'Half-Yearly', '182 days'),
    ('yearly', 'Yearly', '365 days'),
    ('custom', 'Custom', 'specify days'),
  ];

  static const _intervalOptions = [
    ('weekly', 'Weekly', '7 days'),
    ('bi_weekly', 'Bi-Weekly', '14 days'),
    ('monthly', 'Monthly', '30 days'),
    ('custom', 'Custom', 'specify days'),
  ];

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _planName;
  late final TextEditingController _customPkgDays;
  late final TextEditingController _customIntervalDays;
  late final TextEditingController _pricePerVisit;
  late final TextEditingController _discountValue;

  late String _packageDuration;
  late String _serviceInterval;
  late String _discountType;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _planName = TextEditingController(text: e?.planName ?? '');
    _packageDuration = e?.packageDuration ?? 'yearly';
    _customPkgDays = TextEditingController(
        text: e?.packageDurationValue?.toString() ?? '');
    _serviceInterval = e?.serviceInterval ?? 'monthly';
    _customIntervalDays = TextEditingController(
        text: e?.serviceIntervalValue?.toString() ?? '');
    _pricePerVisit = TextEditingController(
        text: e != null ? e.pricePerVisit.toStringAsFixed(2) : '');
    _discountType = e?.discountType ?? 'percentage';
    _discountValue = TextEditingController(
        text: e != null ? e.discountValue.toStringAsFixed(2) : '0');
    _isActive = e?.isActive ?? true;

    _planName.addListener(_rebuild);
    _customPkgDays.addListener(_rebuild);
    _customIntervalDays.addListener(_rebuild);
    _pricePerVisit.addListener(_rebuild);
    _discountValue.addListener(_rebuild);
  }

  @override
  void dispose() {
    _planName.dispose();
    _customPkgDays.dispose();
    _customIntervalDays.dispose();
    _pricePerVisit.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // ── Live preview calculation ─────────────────────────────────────────────

  AmcPlan? get _preview {
    final price =
        widget.servicePrice ?? double.tryParse(_pricePerVisit.text.trim());
    if (price == null) return null;
    final discount = double.tryParse(_discountValue.text.trim()) ?? 0;
    final customPkg = int.tryParse(_customPkgDays.text.trim());
    final customInt = int.tryParse(_customIntervalDays.text.trim());
    return AmcPlan(
      id: '',
      planName: _planName.text.trim(),
      packageDuration: _packageDuration,
      packageDurationValue: customPkg,
      serviceInterval: _serviceInterval,
      serviceIntervalValue: customInt,
      pricePerVisit: price,
      discountType: _discountType,
      discountValue: discount,
      isActive: _isActive,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        planName: _planName.text.trim(),
        packageDuration: _packageDuration,
        packageDurationValue: _packageDuration == 'custom'
            ? int.tryParse(_customPkgDays.text.trim())
            : null,
        serviceInterval: _serviceInterval,
        serviceIntervalValue: _serviceInterval == 'custom'
            ? int.tryParse(_customIntervalDays.text.trim())
            : null,
        pricePerVisit: widget.servicePrice ??
            double.parse(_pricePerVisit.text.trim()),
        discountType: _discountType,
        discountValue: double.tryParse(_discountValue.text.trim()) ?? 0,
        isActive: _isActive,
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
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(isEdit),
            Flexible(child: _buildBody()),
            _buildFooter(isEdit),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isEdit) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Icon(
              isEdit ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              isEdit ? 'Edit AMC Plan' : 'New AMC Plan',
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
      );

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Name
            TextFormField(
              controller: _planName,
              decoration: const InputDecoration(
                labelText: 'Plan Name *',
                hintText: 'e.g. Annual AC Maintenance Plan',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 20),

            // Package Duration
            _label('Package Duration'),
            const SizedBox(height: 6),
            _buildDropdown(
              value: _packageDuration,
              items: _packageOptions,
              onChanged: (v) => setState(() => _packageDuration = v),
            ),
            if (_packageDuration == 'custom') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _customPkgDays,
                decoration: const InputDecoration(
                  labelText: 'Contract Duration (days) *',
                  hintText: 'e.g. 365',
                  suffixText: 'days',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_packageDuration != 'custom') return null;
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid number of days';
                  return null;
                },
              ),
            ],
            const SizedBox(height: 20),

            // Service Interval
            _label('Service Interval'),
            const SizedBox(height: 6),
            _buildDropdown(
              value: _serviceInterval,
              items: _intervalOptions,
              onChanged: (v) => setState(() => _serviceInterval = v),
            ),
            if (_serviceInterval == 'custom') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _customIntervalDays,
                decoration: const InputDecoration(
                  labelText: 'Visit Interval (days) *',
                  hintText: 'e.g. 45',
                  suffixText: 'days',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_serviceInterval != 'custom') return null;
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid number of days';
                  return null;
                },
              ),
            ],
            const SizedBox(height: 20),

            // Price per visit — read-only from catalog or admin-entered
            if (widget.servicePrice != null)
              _buildCatalogPriceDisplay(widget.servicePrice!)
            else
              TextFormField(
                controller: _pricePerVisit,
                decoration: const InputDecoration(
                  labelText: 'Price Per Visit (₹) *',
                  prefixText: '₹ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final p = double.tryParse(v.trim());
                  if (p == null || p < 0) return 'Enter a valid price';
                  return null;
                },
              ),
            const SizedBox(height: 20),

            // Discount
            _label('Discount'),
            const SizedBox(height: 8),
            Row(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'percentage', label: Text('Percentage (%)')),
                    ButtonSegment(value: 'fixed', label: Text('Fixed (₹)')),
                  ],
                  selected: {_discountType},
                  onSelectionChanged: (s) =>
                      setState(() => _discountType = s.first),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _discountValue,
              decoration: InputDecoration(
                labelText: _discountType == 'percentage'
                    ? 'Discount (%)'
                    : 'Discount Amount (₹)',
                prefixText: _discountType == 'fixed' ? '₹ ' : null,
                suffixText: _discountType == 'percentage' ? '%' : null,
                hintText: '0',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
            ),
            const SizedBox(height: 20),

            // Status toggle
            _buildToggleRow(
              icon: Icons.visibility_off_outlined,
              activeIcon: Icons.visibility_rounded,
              label: 'Active',
              subtitle: 'Inactive plans are hidden from customers',
              value: _isActive,
              activeColor: AppColors.success,
              onChanged: (v) => setState(() => _isActive = v),
            ),

            // ── Live preview ──────────────────────────────────────────────
            const SizedBox(height: 24),
            _buildPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogPriceDisplay(double price) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.currency_rupee,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Price Per Visit',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  Text(
                    _currency.format(price),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'From Catalog',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
              ),
            ),
          ],
        ),
      );

  Widget _buildPreview() {
    final p = _preview;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calculate_rounded,
                  size: 15, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Pricing Preview',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (p == null)
            const Text(
              'Enter price per visit to see calculations',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else ...[
            _previewRow('Package Duration', p.packageDurationLabel),
            _previewRow('Service Interval', p.serviceIntervalLabel),
            _previewRow('Number of Visits',
                '${p.numVisits} visit${p.numVisits == 1 ? '' : 's'}'),
            const Divider(height: 16),
            _previewRow('Price Per Visit', _currency.format(p.pricePerVisit)),
            _previewRow('Original Total', _currency.format(p.originalTotal)),
            if (p.discountAmount > 0)
              _previewRow(
                'Discount',
                '- ${_currency.format(p.discountAmount)}'
                    ' (${p.discountType == 'percentage' ? '${p.discountValue.toStringAsFixed(1)}%' : _currency.format(p.discountValue)})',
                color: AppColors.error,
              ),
            const Divider(height: 16),
            _previewRow(
              'Final AMC Price',
              _currency.format(p.finalPrice),
              bold: true,
              color: AppColors.success,
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  color: color ?? AppColors.textSecondary,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
            ),
            Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? AppColors.textPrimary),
            ),
          ],
        ),
      );

  Widget _buildDropdown({
    required String value,
    required List<(String, String, String)> items,
    required ValueChanged<String> onChanged,
  }) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppColors.border, width: 0.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppColors.border, width: 0.8),
          ),
        ),
        items: items
            .map((t) => DropdownMenuItem(
                  value: t.$1,
                  child: Row(
                    children: [
                      Text(t.$2,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      Text(t.$3,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  Widget _buildFooter(bool isEdit) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12)),
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
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isEdit ? 'Save Changes' : 'Create Plan'),
            ),
          ],
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary),
      );

  Widget _buildToggleRow({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String subtitle,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              value ? activeIcon : icon,
              color: value ? activeColor : AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: activeColor,
            ),
          ],
        ),
      );
}
