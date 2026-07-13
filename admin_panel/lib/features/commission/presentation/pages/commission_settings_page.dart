import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/commission_providers.dart';
import '../../domain/models/commission_rule.dart';

class CommissionSettingsPage extends ConsumerStatefulWidget {
  const CommissionSettingsPage({super.key});

  @override
  ConsumerState<CommissionSettingsPage> createState() =>
      _CommissionSettingsPageState();
}

class _CommissionSettingsPageState
    extends ConsumerState<CommissionSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  CommissionRule? _current;
  bool _isEnabled = true;
  String _commissionType = 'percentage';
  final _valueCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rule =
          await ref.read(commissionRepositoryProvider).fetchGlobal();
      if (mounted) _apply(rule);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load settings: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(CommissionRule? rule) {
    _current = rule;
    _isEnabled = rule?.isEnabled ?? true;
    _commissionType = rule?.commissionType ?? 'percentage';
    final v = rule?.commissionValue ?? 10.0;
    _valueCtrl.text = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toString();
  }

  Future<void> _save() async {
    final value = double.tryParse(_valueCtrl.text.trim());
    if (value == null || value < 0) {
      setState(() => _error = 'Enter a valid non-negative number.');
      return;
    }
    if (_commissionType == 'percentage' && value > 100) {
      setState(() => _error = 'Percentage cannot exceed 100.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(commissionRepositoryProvider).upsertRule(
            ruleType: 'global',
            commissionType: _commissionType,
            commissionValue: value,
            isEnabled: _isEnabled,
          );
      if (mounted) {
        ref.invalidate(globalCommissionProvider);
        setState(() => _current = saved);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Commission settings saved.'),
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
                'Commission Settings',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Configure the default platform commission applied to vendor earnings.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              _InfoBanner(children: [
                _BulletRow(
                    text: 'Global commission applies to all vendors by default.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Per-vendor overrides take priority over this global setting.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Per-category overrides are used when no vendor override exists.'),
                const SizedBox(height: 4),
                _BulletRow(
                    text: 'Commission is shown in the settlement dialog and deducted from vendor payouts.'),
              ]),
              const SizedBox(height: 24),

              // Status
              _Card(
                title: 'Status',
                child: Row(
                  children: [
                    Icon(
                      _isEnabled
                          ? Icons.percent_rounded
                          : Icons.money_off_rounded,
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
                                ? 'Commission Enabled'
                                : 'Commission Disabled',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _isEnabled
                                ? 'Platform commission will be deducted from vendor payouts.'
                                : 'No commission will be charged. Vendors receive 100% of earnings.',
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

              // Commission Type
              _Card(
                title: 'Commission Type',
                child: Row(
                  children: [
                    Expanded(
                      child: _TypeButton(
                        label: 'Percentage (%)',
                        icon: Icons.percent_rounded,
                        selected: _commissionType == 'percentage',
                        onTap: () =>
                            setState(() => _commissionType = 'percentage'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TypeButton(
                        label: 'Fixed Amount (₹)',
                        icon: Icons.currency_rupee_rounded,
                        selected: _commissionType == 'fixed',
                        onTap: () =>
                            setState(() => _commissionType = 'fixed'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Commission Value
              _Card(
                title: 'Commission Value',
                child: TextFormField(
                  controller: _valueCtrl,
                  decoration: InputDecoration(
                    hintText: _commissionType == 'percentage' ? 'e.g. 10' : 'e.g. 50',
                    suffixText: _commissionType == 'percentage' ? '%' : '₹',
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
                          'Save Commission Settings',
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

// ── Sub-widgets ────────────────────────────────────────────────────────────────

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
                'How commission works',
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
