import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';

class LoyaltyPage extends StatefulWidget {
  const LoyaltyPage({super.key});

  @override
  State<LoyaltyPage> createState() => _LoyaltyPageState();
}

class _LoyaltyPageState extends State<LoyaltyPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String? _settingsId;

  final _earnPer100 = TextEditingController();
  final _minRedeemPoints = TextEditingController();
  final _maxRedeemPct = TextEditingController();
  bool _isEnabled = true;
  bool _earnEnabled = true;
  bool _redeemEnabled = true;

  List<Map<String, dynamic>> _stats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _earnPer100.dispose();
    _minRedeemPoints.dispose();
    _maxRedeemPct.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await _client
          .from('loyalty_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (settings != null) {
        _settingsId = settings['id'] as String;
        _isEnabled = settings['is_enabled'] as bool? ?? true;
        _earnEnabled = settings['earn_enabled'] as bool? ?? true;
        _redeemEnabled = settings['redeem_enabled'] as bool? ?? true;
        _earnPer100.text = '${settings['earn_per_100'] ?? 10}';
        _minRedeemPoints.text = '${settings['minimum_redeem_points'] ?? 100}';
        _maxRedeemPct.text =
            '${(settings['max_redeem_percentage'] as num?)?.toInt() ?? 20}';
      } else {
        _earnPer100.text = '10';
        _minRedeemPoints.text = '100';
        _maxRedeemPct.text = '20';
      }

      // Stats
      final membersData = await _client.from('customer_loyalty').select('customer_id');
      final earnData = await _client
          .from('loyalty_transactions')
          .select('points')
          .eq('transaction_type', 'earn');
      final redeemData = await _client
          .from('loyalty_transactions')
          .select('points')
          .eq('transaction_type', 'redeem');

      int earnedSum = 0;
      int redeemedSum = 0;
      for (final row in (earnData as List)) {
        earnedSum += (row['points'] as int? ?? 0);
      }
      for (final row in (redeemData as List)) {
        redeemedSum += (row['points'] as int? ?? 0);
      }

      setState(() {
        _stats = [
          {
            'label': 'Active Members',
            'value': '${(membersData as List).length}',
            'icon': Icons.people_rounded,
            'color': const Color(0xFF3182CE),
          },
          {
            'label': 'Total Pts Earned',
            'value': '$earnedSum',
            'icon': Icons.trending_up_rounded,
            'color': const Color(0xFF38A169),
          },
          {
            'label': 'Total Pts Redeemed',
            'value': '$redeemedSum',
            'icon': Icons.redeem_rounded,
            'color': const Color(0xFFD69E2E),
          },
        ];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Failed to load loyalty settings: $e', isError: true);
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'is_enabled': _isEnabled,
        'earn_enabled': _earnEnabled,
        'redeem_enabled': _redeemEnabled,
        'earn_per_100': int.parse(_earnPer100.text.trim()),
        'minimum_redeem_points': int.parse(_minRedeemPoints.text.trim()),
        'max_redeem_percentage': double.parse(_maxRedeemPct.text.trim()),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_settingsId != null) {
        await _client
            .from('loyalty_settings')
            .update(payload)
            .eq('id', _settingsId!);
      } else {
        final row = await _client
            .from('loyalty_settings')
            .insert(payload)
            .select()
            .single();
        _settingsId = row['id'] as String;
      }
      if (mounted) _showSnack('Settings saved.');
    } catch (e) {
      if (mounted) _showSnack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
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
              // ── Header ──────────────────────────────────────────────────────
              const Text(
                'Loyalty Programme',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Configure how customers earn and redeem loyalty points.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // ── Stats row ────────────────────────────────────────────────────
              if (_stats.isNotEmpty) ...[
                Row(
                  children: _stats
                      .map((s) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(right: 12),
                              child: _StatCard(
                                label: s['label'] as String,
                                value: s['value'] as String,
                                icon: s['icon'] as IconData,
                                color: s['color'] as Color,
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],

              // ── Settings form ────────────────────────────────────────────────
              _Card(
                title: 'Settings',
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _SwitchRow(
                        label: 'Programme Enabled',
                        subtitle: 'Master switch — disables all earn & redeem when off.',
                        value: _isEnabled,
                        onChanged: (v) => setState(() => _isEnabled = v),
                      ),
                      const Divider(height: 24),
                      _SwitchRow(
                        label: 'Earning Enabled',
                        subtitle: 'Customers earn points on completed bookings.',
                        value: _earnEnabled,
                        onChanged: (v) => setState(() => _earnEnabled = v),
                      ),
                      const SizedBox(height: 16),
                      _NumberField(
                        controller: _earnPer100,
                        label: 'Points per ₹100',
                        hint: 'e.g. 10',
                        suffix: 'pts',
                        min: 1,
                        max: 9999,
                      ),
                      const Divider(height: 24),
                      _SwitchRow(
                        label: 'Redemption Enabled',
                        subtitle: 'Customers can redeem points at checkout.',
                        value: _redeemEnabled,
                        onChanged: (v) => setState(() => _redeemEnabled = v),
                      ),
                      const SizedBox(height: 16),
                      _NumberField(
                        controller: _minRedeemPoints,
                        label: 'Minimum Points to Redeem',
                        hint: 'e.g. 100',
                        suffix: 'pts',
                        min: 1,
                        max: 99999,
                      ),
                      const SizedBox(height: 16),
                      _NumberField(
                        controller: _maxRedeemPct,
                        label: 'Max Redeem % of Order',
                        hint: 'e.g. 20',
                        suffix: '%',
                        min: 1,
                        max: 100,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save Settings',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Rate info card ───────────────────────────────────────────────
              _Card(
                title: 'How Points Work',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: Icons.add_circle_outline_rounded,
                      color: const Color(0xFF38A169),
                      text:
                          'Earn: floor(booking_amount / 100) × earn_per_100 pts — awarded automatically when a booking is marked Completed.',
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.redeem_rounded,
                      color: const Color(0xFFD69E2E),
                      text:
                          'Redeem: 1 point = ₹1 off, capped at max_redeem_percentage of the order total, requires min_redeem_points.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String suffix;
  final int min;
  final int max;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.suffix,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: (v) {
        final n = int.tryParse(v ?? '');
        if (n == null) return 'Enter a valid number';
        if (n < min || n > max) return 'Must be $min–$max';
        return null;
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
