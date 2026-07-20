import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/surge_fee_settings_repository.dart';

class SurgeFeeSettingsPage extends StatefulWidget {
  const SurgeFeeSettingsPage({super.key});

  @override
  State<SurgeFeeSettingsPage> createState() => _SurgeFeeSettingsPageState();
}

class _SurgeFeeSettingsPageState extends State<SurgeFeeSettingsPage> {
  final _repo = SurgeFeeSettingsRepository(Supabase.instance.client);

  bool _loading = true;
  bool _saving = false;
  String? _error;

  SurgeFeeConfig? _current;

  bool _isEnabled = false;
  final _surgeName = TextEditingController();
  String _surgeType = 'percentage'; // 'percentage' | 'fixed'
  final _surgeValue = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _surgeName.dispose();
    _surgeValue.dispose();
    _description.dispose();
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

  void _apply(SurgeFeeConfig cfg) {
    _current = cfg;
    _isEnabled = cfg.isEnabled;
    _surgeName.text = cfg.surgeName;
    _surgeType = cfg.surgeType;
    _surgeValue.text = cfg.surgeValue == cfg.surgeValue.truncateToDouble()
        ? cfg.surgeValue.toInt().toString()
        : cfg.surgeValue.toString();
    _description.text = cfg.description ?? '';
  }

  Future<void> _save() async {
    final name = _surgeName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Surge fee name cannot be empty.');
      return;
    }
    final value = double.tryParse(_surgeValue.text.trim());
    if (value == null || value < 0) {
      setState(() => _error = 'Value must be a valid non-negative number.');
      return;
    }
    if (_surgeType == 'percentage' && value > 100) {
      setState(() => _error = 'Percentage cannot exceed 100.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = SurgeFeeConfig(
        id: _current?.id,
        isEnabled: _isEnabled,
        surgeName: name,
        surgeType: _surgeType,
        surgeValue: value,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
      );
      final saved = await _repo.save(updated);
      if (mounted) {
        setState(() => _current = saved);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Surge fee settings saved.'),
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
              const Text(
                'Surge Fee',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Configure an optional surge charge applied to the order subtotal at checkout.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              _InfoBanner(children: [
                _BulletRow(
                    text: 'Surge fee is applied to the subtotal before GST.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Percentage surge is calculated as a fraction of the subtotal.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Fixed surge adds a flat amount regardless of order size.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Per-catalog overrides can be set in the Catalog module config.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Disabling surge sets it to ₹0 at checkout without '
                        'changing existing booking records.'),
              ]),
              const SizedBox(height: 24),

              // ── Status ──────────────────────────────────────────────────────
              _Card(
                title: 'Status',
                child: Row(
                  children: [
                    Icon(
                      _isEnabled
                          ? Icons.bolt_rounded
                          : Icons.bolt_outlined,
                      color: _isEnabled
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEnabled ? 'Surge Fee Enabled' : 'Surge Fee Disabled',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _isEnabled
                                ? 'A surge charge will be added to orders at checkout.'
                                : 'No surge charge will be applied at checkout.',
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
                      activeColor: AppColors.warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Charge Name ─────────────────────────────────────────────────
              _Card(
                title: 'Charge Name',
                child: TextFormField(
                  controller: _surgeName,
                  decoration: InputDecoration(
                    hintText: 'e.g. Surge Fee, Peak Hours, Holiday Surcharge',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Surge Type ──────────────────────────────────────────────────
              _Card(
                title: 'Charge Type',
                child: Row(
                  children: [
                    Expanded(
                      child: _TypeButton(
                        label: 'Percentage (%)',
                        icon: Icons.percent_rounded,
                        selected: _surgeType == 'percentage',
                        onTap: () =>
                            setState(() => _surgeType = 'percentage'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TypeButton(
                        label: 'Fixed Amount (₹)',
                        icon: Icons.currency_rupee_rounded,
                        selected: _surgeType == 'fixed',
                        onTap: () => setState(() => _surgeType = 'fixed'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Surge Value ─────────────────────────────────────────────────
              _Card(
                title: 'Charge Value',
                child: TextFormField(
                  controller: _surgeValue,
                  decoration: InputDecoration(
                    hintText:
                        _surgeType == 'percentage' ? 'e.g. 10' : 'e.g. 50',
                    suffixText: _surgeType == 'percentage' ? '%' : '₹',
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

              // ── Description ─────────────────────────────────────────────────
              _Card(
                title: 'Description (optional)',
                child: TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. Applied during peak hours to manage demand.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: _error!),
              ],

              const SizedBox(height: 24),

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
                          'Save Surge Fee Settings',
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
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
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
                'How surge fee works',
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
