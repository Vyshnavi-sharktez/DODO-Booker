import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/clickable.dart';
import '../../../service_attributes/application/providers/service_attributes_providers.dart';
import '../../../service_attributes/domain/models/service_attribute.dart';
import '../../../service_attributes/domain/models/service_attribute_option.dart';
import '../../../services/application/providers/services_providers.dart';
import '../../../services/domain/models/service.dart';
import '../../application/providers/pricing_providers.dart';

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

// ── Page ──────────────────────────────────────────────────────────────────────

class PricingEnginePage extends ConsumerStatefulWidget {
  const PricingEnginePage({super.key});

  @override
  ConsumerState<PricingEnginePage> createState() => _PricingEnginePageState();
}

class _PricingEnginePageState extends ConsumerState<PricingEnginePage> {
  String? _selectedServiceId;

  void _onServiceChanged(String? serviceId) {
    if (serviceId == null || serviceId == _selectedServiceId) return;
    setState(() => _selectedServiceId = serviceId);
    ref
        .read(serviceAttributesNotifierProvider.notifier)
        .loadForService(serviceId);
    ref.read(pricingCalculatorProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final servicesState = ref.watch(servicesNotifierProvider);
    final services = servicesState.valueOrNull ?? [];
    final selectedService = _selectedServiceId == null
        ? null
        : services.where((s) => s.id == _selectedServiceId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pricing Engine',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage price adjustments and preview service pricing',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Service selector ──────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Service:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 340,
                child: servicesState.isLoading
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedServiceId,
                        decoration: const InputDecoration(
                          hintText: 'Select a service…',
                          prefixIcon: Icon(Icons.home_repair_service_rounded,
                              size: 18),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        isExpanded: true,
                        items: services
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: _onServiceChanged,
                      ),
              ),
              if (selectedService != null) ...[
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Base Price: ',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        _currency.format(selectedService.basePrice),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // ── Two-panel body ────────────────────────────────────────────────
          Expanded(
            child: _selectedServiceId == null || selectedService == null
                ? const _NoServiceState()
                : _TwoPanelBody(
                    service: selectedService,
                    serviceId: _selectedServiceId!,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Two-panel layout ──────────────────────────────────────────────────────────

class _TwoPanelBody extends ConsumerWidget {
  final Service service;
  final String serviceId;

  const _TwoPanelBody({required this.service, required this.serviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attrsState = ref.watch(serviceAttributesNotifierProvider);

    return attrsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Failed to load attributes',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(e.toString(),
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ref
                  .read(serviceAttributesNotifierProvider.notifier)
                  .refresh(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (attributes) {
        final optionAttrs =
            attributes.where((a) => a.hasOptions).toList();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: adjustments
            Expanded(
              flex: 6,
              child: _PriceAdjustmentsPanel(
                attributes: optionAttrs,
                service: service,
              ),
            ),
            const SizedBox(width: 16),
            // Right: calculator
            Expanded(
              flex: 4,
              child: _PricingCalculatorPanel(
                service: service,
                attributes: optionAttrs,
                serviceId: serviceId,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Left panel: Price Adjustments ─────────────────────────────────────────────

class _PriceAdjustmentsPanel extends StatelessWidget {
  final List<ServiceAttribute> attributes;
  final Service service;

  const _PriceAdjustmentsPanel({
    required this.attributes,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.price_change_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Price Adjustments',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '— ${service.name}',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: attributes.isEmpty
                ? const _NoOptionsState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: attributes.length,
                    separatorBuilder: (ctx, i) =>
                        const SizedBox(height: 16),
                    itemBuilder: (ctx, i) => _AttributeGroup(
                      attribute: attributes[i],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Attribute group ────────────────────────────────────────────────────────────

class _AttributeGroup extends StatelessWidget {
  final ServiceAttribute attribute;

  const _AttributeGroup({required this.attribute});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attribute header
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              attribute.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${attribute.options.length} option${attribute.options.length == 1 ? '' : 's'}',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (attribute.options.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(
              'No options defined. Add options in Service Attributes.',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic),
            ),
          )
        else
          ...attribute.options.map(
            (opt) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _OptionPriceRow(option: opt),
            ),
          ),
      ],
    );
  }
}

// ── Option price row (inline edit) ────────────────────────────────────────────

class _OptionPriceRow extends ConsumerStatefulWidget {
  final ServiceAttributeOption option;

  const _OptionPriceRow({required this.option});

  @override
  ConsumerState<_OptionPriceRow> createState() => _OptionPriceRowState();
}

class _OptionPriceRowState extends ConsumerState<_OptionPriceRow> {
  late final TextEditingController _controller;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.option.priceAdjustment));
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _OptionPriceRow old) {
    super.didUpdateWidget(old);
    if (old.option.priceAdjustment != widget.option.priceAdjustment &&
        !_dirty) {
      _controller.removeListener(_onChanged);
      _controller.text = _fmt(widget.option.priceAdjustment);
      _controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == 0 ? '0' : v.toStringAsFixed(2);

  void _onChanged() {
    final parsed = double.tryParse(_controller.text) ?? 0.0;
    final isDirty = parsed != widget.option.priceAdjustment;
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  Future<void> _save() async {
    final value = double.tryParse(_controller.text.trim()) ?? 0.0;
    setState(() => _saving = true);
    try {
      await ref
          .read(serviceAttributesNotifierProvider.notifier)
          .updateOption(
            widget.option.id,
            optionName: widget.option.optionName,
            priceAdjustment: value,
          );
      setState(() => _dirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '"${widget.option.optionName}" updated to ${_fmtDisplay(value)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearToZero() {
    _controller.text = '0';
  }

  String _fmtDisplay(double v) {
    if (v == 0) return '₹0 (no adjustment)';
    final sign = v > 0 ? '+' : '';
    return '$sign₹${v.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.option.priceAdjustment;
    final priceColor = v == 0
        ? AppColors.textSecondary
        : v > 0
            ? AppColors.success
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _dirty
            ? AppColors.accent.withValues(alpha: 0.04)
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _dirty
              ? AppColors.accent.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Option name
          Expanded(
            flex: 4,
            child: Text(
              widget.option.optionName,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Current adjustment badge (shown when not dirty)
          if (!_dirty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: priceColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: priceColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  _fmtDisplay(v),
                  style: TextStyle(
                    fontSize: 11,
                    color: priceColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // Price input
          SizedBox(
            width: 100,
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                prefixText: '₹ ',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: _dirty ? AppColors.accent : AppColors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^-?\d*\.?\d{0,2}')),
              ],
              onSubmitted: (_) {
                if (_dirty) _save();
              },
            ),
          ),
          const SizedBox(width: 4),

          // Clear to zero
          if (_dirty || v != 0)
            Tooltip(
              message: 'Clear to ₹0',
              child: IconButton(
                onPressed: _clearToZero,
                icon: const Icon(Icons.backspace_outlined, size: 14),
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),

          // Save button
          if (_dirty)
            _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Tooltip(
                    message: 'Save',
                    child: IconButton(
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      color: AppColors.success,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
        ],
      ),
    );
  }
}

// ── Right panel: Pricing Calculator ──────────────────────────────────────────

class _PricingCalculatorPanel extends ConsumerWidget {
  final Service service;
  final List<ServiceAttribute> attributes;
  final String serviceId;

  const _PricingCalculatorPanel({
    required this.service,
    required this.attributes,
    required this.serviceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selections = ref.watch(pricingCalculatorProvider);
    final finalPrice = ref.watch(calculatedPriceProvider(serviceId));
    final breakdown = ref.watch(calculatorBreakdownProvider(serviceId));
    final hasSelections = selections.isNotEmpty;

    final optionAttrs =
        attributes.where((a) => a.options.isNotEmpty).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calculate_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Pricing Calculator',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (hasSelections)
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(pricingCalculatorProvider.notifier).reset(),
                    icon: const Icon(Icons.refresh_rounded, size: 13),
                    label: const Text('Reset',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

          // Selectors
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (optionAttrs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No options available for calculation.\nAdd options with price adjustments first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    )
                  else ...[
                    ...optionAttrs.map(
                      (attr) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _CalculatorAttributeSelector(
                          attribute: attr,
                          selectedOptionId: selections[attr.id],
                          onSelect: (optionId) => ref
                              .read(pricingCalculatorProvider.notifier)
                              .selectOption(attr.id, optionId),
                          onClear: () => ref
                              .read(pricingCalculatorProvider.notifier)
                              .clearAttribute(attr.id),
                        ),
                      ),
                    ),
                  ],

                  const Divider(height: 24),

                  // ── Price breakdown ────────────────────────────────────────
                  _PriceBreakdown(
                    service: service,
                    breakdown: breakdown,
                    finalPrice: finalPrice,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Calculator attribute selector ─────────────────────────────────────────────

class _CalculatorAttributeSelector extends StatelessWidget {
  final ServiceAttribute attribute;
  final String? selectedOptionId;
  final void Function(String) onSelect;
  final VoidCallback onClear;

  const _CalculatorAttributeSelector({
    required this.attribute,
    required this.selectedOptionId,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              attribute.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            if (selectedOptionId != null) ...[
              const Spacer(),
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: attribute.options.map((opt) {
            final isSelected = opt.id == selectedOptionId;
            final adjColor = opt.priceAdjustment == 0
                ? AppColors.textSecondary
                : opt.priceAdjustment > 0
                    ? AppColors.success
                    : AppColors.error;
            final adjStr = opt.priceAdjustment == 0
                ? '±₹0'
                : opt.priceAdjustment > 0
                    ? '+₹${opt.priceAdjustment.toStringAsFixed(0)}'
                    : '−₹${opt.priceAdjustment.abs().toStringAsFixed(0)}';

            return Clickable(
              onTap: () => onSelect(opt.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected) ...[
                      const Icon(Icons.check_circle_rounded,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      opt.optionName,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      adjStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? adjColor : adjColor.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Price breakdown ───────────────────────────────────────────────────────────

class _PriceBreakdown extends StatelessWidget {
  final Service service;
  final List<(String, String, double)> breakdown;
  final double finalPrice;

  const _PriceBreakdown({
    required this.service,
    required this.breakdown,
    required this.finalPrice,
  });

  @override
  Widget build(BuildContext context) {
    final totalAdjustment =
        breakdown.fold<double>(0.0, (sum, row) => sum + row.$3);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PRICE PREVIEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          // Base price row
          _BreakdownRow(
            label: 'Base Price',
            sublabel: service.name,
            value: service.basePrice,
            isBase: true,
          ),

          // Adjustment rows
          if (breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Select options above to see adjustments.',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            ...breakdown.map(
              (row) => _BreakdownRow(
                label: row.$1,
                sublabel: row.$2,
                value: row.$3,
              ),
            ),
          ],

          // Separator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.add_rounded,
                      size: 14, color: AppColors.textSecondary),
                ),
                Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
          ),

          // Total adjustment
          if (breakdown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    'Total Adjustments',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    _fmtAdj(totalAdjustment),
                    style: TextStyle(
                      fontSize: 12,
                      color: totalAdjustment == 0
                          ? AppColors.textSecondary
                          : totalAdjustment > 0
                              ? AppColors.success
                              : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Final price
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Text(
                  'Final Price',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  _currency.format(finalPrice),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtAdj(double v) {
    if (v == 0) return '₹0';
    final sign = v > 0 ? '+' : '';
    return '$sign₹${v.toStringAsFixed(2)}';
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final double value;
  final bool isBase;

  const _BreakdownRow({
    required this.label,
    required this.sublabel,
    required this.value,
    this.isBase = false,
  });

  @override
  Widget build(BuildContext context) {
    final sign = isBase ? '' : (value >= 0 ? '+' : '');
    final valStr = isBase
        ? _currency.format(value)
        : '$sign₹${value.toStringAsFixed(2)}';
    final valColor = isBase
        ? AppColors.textPrimary
        : value == 0
            ? AppColors.textSecondary
            : value > 0
                ? AppColors.success
                : AppColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                Text(sublabel,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(
            valStr,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  isBase ? FontWeight.w700 : FontWeight.w600,
              color: valColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty states ──────────────────────────────────────────────────────────────

class _NoServiceState extends StatelessWidget {
  const _NoServiceState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.price_change_outlined,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a service',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a service above to manage its pricing.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _NoOptionsState extends StatelessWidget {
  const _NoOptionsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_outlined,
              size: 48,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No options to configure',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add dropdown, radio, or checkbox attributes\nwith options in Service Attributes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
