import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/tax_settings_repository.dart';

class TaxSettingsPage extends StatefulWidget {
  const TaxSettingsPage({super.key});

  @override
  State<TaxSettingsPage> createState() => _TaxSettingsPageState();
}

class _TaxSettingsPageState extends State<TaxSettingsPage> {
  final _repo = TaxSettingsRepository(Supabase.instance.client);

  bool _loading = true;
  bool _saving = false;
  String? _error;

  TaxSettingsConfig? _current;

  bool _isEnabled = true;
  final _taxName = TextEditingController();
  String _taxType = 'percentage'; // 'percentage' | 'fixed'
  final _taxValue = TextEditingController();
  bool _applyOnServices = true;
  bool _applyOnAddons = true;
  bool _applyOnPackages = false;
  bool _displaySeparately = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _taxName.dispose();
    _taxValue.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await _repo.fetch();
      _apply(cfg);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load settings: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(TaxSettingsConfig cfg) {
    _current = cfg;
    _isEnabled = cfg.isEnabled;
    _taxName.text = cfg.taxName;
    _taxType = cfg.taxType;
    _taxValue.text = cfg.taxValue == cfg.taxValue.truncateToDouble()
        ? cfg.taxValue.toInt().toString()
        : cfg.taxValue.toString();
    _applyOnServices = cfg.applyOnServices;
    _applyOnAddons = cfg.applyOnAddons;
    _applyOnPackages = cfg.applyOnPackages;
    _displaySeparately = cfg.displaySeparately;
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _taxName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Tax name cannot be empty.');
      return;
    }
    final value = double.tryParse(_taxValue.text.trim());
    if (value == null || value < 0) {
      setState(
          () => _error = 'Tax value must be a valid non-negative number.');
      return;
    }
    if (_taxType == 'percentage' && value > 100) {
      setState(() => _error = 'Percentage cannot exceed 100.');
      return;
    }
    if (_isEnabled && !_applyOnServices && !_applyOnAddons && !_applyOnPackages) {
      setState(() => _error = 'Select at least one item type to apply tax on.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = TaxSettingsConfig(
        id: _current?.id,
        isEnabled: _isEnabled,
        taxName: name,
        taxType: _taxType,
        taxValue: value,
        applyOnServices: _applyOnServices,
        applyOnAddons: _applyOnAddons,
        applyOnPackages: _applyOnPackages,
        displaySeparately: _displaySeparately,
      );
      final saved = await _repo.save(updated);
      if (mounted) {
        setState(() => _current = saved);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tax settings saved.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
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
                'Tax Settings',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Configure how tax is calculated and displayed in the customer checkout.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // ── Info banner ──────────────────────────────────────────────────
              _InfoBanner(children: [
                _BulletRow(
                    text: 'Tax is applied to the order subtotal at checkout.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Percentage tax is calculated as a fraction of the '
                        'subtotal (e.g. 18% GST).'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Fixed tax adds a flat amount regardless of '
                        'order size.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Disabling tax sets it to ₹0 at checkout without '
                        'changing existing booking records.'),
              ]),
              const SizedBox(height: 24),

              // ── Status ───────────────────────────────────────────────────────
              _Card(
                title: 'Status',
                child: Row(
                  children: [
                    Icon(
                      _isEnabled
                          ? Icons.receipt_long_rounded
                          : Icons.receipt_outlined,
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
                            _isEnabled ? 'Tax Enabled' : 'Tax Disabled',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _isEnabled
                                ? 'Tax will be added to orders at checkout.'
                                : 'No tax will be charged at checkout.',
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

              // ── Tax Name ─────────────────────────────────────────────────────
              _Card(
                title: 'Tax Name',
                child: TextFormField(
                  controller: _taxName,
                  decoration: InputDecoration(
                    hintText: 'e.g. GST, VAT, Service Tax',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Tax Type ─────────────────────────────────────────────────────
              _Card(
                title: 'Tax Type',
                child: Row(
                  children: [
                    Expanded(
                      child: _TypeButton(
                        label: 'Percentage (%)',
                        icon: Icons.percent_rounded,
                        selected: _taxType == 'percentage',
                        onTap: () =>
                            setState(() => _taxType = 'percentage'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TypeButton(
                        label: 'Fixed Amount (₹)',
                        icon: Icons.currency_rupee_rounded,
                        selected: _taxType == 'fixed',
                        onTap: () => setState(() => _taxType = 'fixed'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Tax Value ────────────────────────────────────────────────────
              _Card(
                title: 'Tax Value',
                child: TextFormField(
                  controller: _taxValue,
                  decoration: InputDecoration(
                    hintText: _taxType == 'percentage' ? 'e.g. 18' : 'e.g. 50',
                    suffixText:
                        _taxType == 'percentage' ? '%' : '₹',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,4}')),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Applies On ───────────────────────────────────────────────────
              _Card(
                title: 'Applies On',
                child: Column(
                  children: [
                    _CheckRow(
                      label: 'Services',
                      subtitle: 'All booked services in the cart.',
                      value: _applyOnServices,
                      onChanged: (v) =>
                          setState(() => _applyOnServices = v ?? false),
                    ),
                    const Divider(height: 16, color: AppColors.border),
                    _CheckRow(
                      label: 'Add-ons',
                      subtitle: 'Additional add-ons selected with a service.',
                      value: _applyOnAddons,
                      onChanged: (v) =>
                          setState(() => _applyOnAddons = v ?? false),
                    ),
                    const Divider(height: 16, color: AppColors.border),
                    _CheckRow(
                      label: 'Packages',
                      subtitle: 'Bundled service packages.',
                      value: _applyOnPackages,
                      onChanged: (v) =>
                          setState(() => _applyOnPackages = v ?? false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Display Separately ───────────────────────────────────────────
              _Card(
                title: 'Display',
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Show tax as a separate line',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _displaySeparately
                                ? 'Tax appears as its own line in the '
                                    'checkout price summary.'
                                : 'Tax is silently included in the total '
                                    'without a separate line.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _displaySeparately,
                      onChanged: (v) =>
                          setState(() => _displaySeparately = v),
                      activeColor: AppColors.primary,
                    ),
                  ],
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
                          'Save Tax Settings',
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

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
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
                'How tax settings work',
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
