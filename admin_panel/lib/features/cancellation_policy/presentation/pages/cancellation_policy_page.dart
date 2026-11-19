import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/cancellation_policy_providers.dart';
import '../../data/cancellation_policy_repository.dart';
import '../../domain/models/cancellation_policy.dart';

class CancellationPolicyPage extends ConsumerWidget {
  const CancellationPolicyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policiesAsync = ref.watch(cancellationPoliciesProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(onRefresh: () => ref.invalidate(cancellationPoliciesProvider)),
          Expanded(
            child: policiesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Error loading policies: $e',
                      style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.invalidate(cancellationPoliciesProvider),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
              data: (policies) => _PoliciesBody(policies: policies),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  const _Header({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.money_off_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cancellation Policy',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 2),
                Text('Configure fees charged when customers cancel bookings',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _PoliciesBody extends StatelessWidget {
  final List<CancellationPolicy> policies;
  const _PoliciesBody({required this.policies});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: policies
                      .map((p) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: p == policies.last ? 0 : 20),
                              child: _PolicyCard(policy: p),
                            ),
                          ))
                      .toList(),
                );
              }
              return Column(
                children: policies
                    .map((p) => Padding(
                          padding: EdgeInsets.only(
                              bottom: p == policies.last ? 0 : 20),
                          child: _PolicyCard(policy: p),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D4ED8).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1D4ED8).withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF1D4ED8)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cancellation fees are DODO platform revenue — they are never paid to vendors. '
              'For online payments, the fee is deducted from the refund. For COD bookings, '
              'the fee is added to the customer\'s outstanding balance and collected at their next checkout.',
              style: TextStyle(fontSize: 13, color: Color(0xFF1D4ED8), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Policy card ───────────────────────────────────────────────────────────────

class _PolicyCard extends ConsumerStatefulWidget {
  final CancellationPolicy policy;
  const _PolicyCard({required this.policy});

  @override
  ConsumerState<_PolicyCard> createState() => _PolicyCardState();
}

class _PolicyCardState extends ConsumerState<_PolicyCard> {
  bool _toggling = false;

  Future<void> _toggle(bool value) async {
    setState(() => _toggling = true);
    try {
      final repo = CancellationPolicyRepository(Supabase.instance.client);
      await repo.togglePolicy(widget.policy.id, isEnabled: value);
      ref.invalidate(cancellationPoliciesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _addSlab() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SlabDialog(
        policyId: widget.policy.id,
        policyType: widget.policy.policyType,
      ),
    );
    if (result == true) ref.invalidate(cancellationPoliciesProvider);
  }

  Future<void> _editSlab(CancellationPolicySlab slab) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SlabDialog(
        policyId: widget.policy.id,
        policyType: widget.policy.policyType,
        existing: slab,
      ),
    );
    if (result == true) ref.invalidate(cancellationPoliciesProvider);
  }

  Future<void> _deleteSlab(CancellationPolicySlab slab) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Slab?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
            'Remove "${slab.rangeLabel}" slab (₹${slab.feeAmount.toStringAsFixed(0)} fee)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = CancellationPolicyRepository(Supabase.instance.client);
      await repo.deleteSlab(slab.id!);
      ref.invalidate(cancellationPoliciesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.policy;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (p.isEnabled ? AppColors.primary : AppColors.textSecondary)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    p.isBeforeAssignment
                        ? Icons.pending_actions_rounded
                        : Icons.assignment_turned_in_rounded,
                    size: 18,
                    color: p.isEnabled ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.label,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (p.description != null) ...[
                        const SizedBox(height: 2),
                        Text(p.description!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _toggling
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch(
                        value: p.isEnabled,
                        onChanged: _toggle,
                        activeColor: AppColors.success,
                      ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Status badge
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (p.isEnabled
                        ? const Color(0xFF16A34A)
                        : AppColors.textSecondary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p.isEnabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: p.isEnabled
                      ? const Color(0xFF16A34A)
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),

          // Time dimension hint
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  p.isBeforeAssignment
                      ? 'Time dimension: hours elapsed since booking was placed'
                      : 'Time dimension: hours remaining until scheduled service',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Slabs section
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(children: [
              const Text('Time Slabs',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addSlab,
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Add Slab'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),

          if (p.slabs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Text('No slabs configured — all cancellations are free.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
              ),
            )
          else ...[
            // Column headers
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(children: const [
                Expanded(flex: 2, child: Text('Range', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('Fee', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                Expanded(flex: 3, child: Text('Label', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                SizedBox(width: 72),
              ]),
            ),
            const Divider(height: 1),
            ...p.slabs.map((slab) => _SlabRow(
                  slab: slab,
                  onEdit: () => _editSlab(slab),
                  onDelete: () => _deleteSlab(slab),
                )),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SlabRow extends StatelessWidget {
  final CancellationPolicySlab slab;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SlabRow(
      {required this.slab, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: Text(slab.rangeLabel,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        Expanded(
          flex: 2,
          child: Text(
            slab.feeAmount == 0
                ? 'Free'
                : '₹${slab.feeAmount.toStringAsFixed(0)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: slab.feeAmount == 0 ? const Color(0xFF16A34A) : AppColors.error),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            slab.label ?? '—',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(children: [
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 16),
            color: AppColors.primary,
            tooltip: 'Edit',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: slab.id != null ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            color: AppColors.error,
            tooltip: 'Delete',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ]),
      ]),
    );
  }
}

// ── Slab edit dialog ──────────────────────────────────────────────────────────

class _SlabDialog extends StatefulWidget {
  final String policyId;
  final String policyType;
  final CancellationPolicySlab? existing;

  const _SlabDialog({
    required this.policyId,
    required this.policyType,
    this.existing,
  });

  @override
  State<_SlabDialog> createState() => _SlabDialogState();
}

class _SlabDialogState extends State<_SlabDialog> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  bool _openEnded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fromCtrl.text = _minsToHrs(e?.fromMinutes ?? 0);
    _toCtrl.text = e?.toMinutes != null ? _minsToHrs(e!.toMinutes!) : '';
    _feeCtrl.text = e != null ? e.feeAmount.toStringAsFixed(0) : '';
    _labelCtrl.text = e?.label ?? '';
    _orderCtrl.text = (e?.sortOrder ?? 0).toString();
    _openEnded = e?.toMinutes == null && e != null;
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _feeCtrl.dispose();
    _labelCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  static String _minsToHrs(int minutes) {
    final hrs = minutes / 60.0;
    return hrs == hrs.truncateToDouble() ? hrs.toInt().toString() : hrs.toStringAsFixed(1);
  }

  Future<void> _save() async {
    final fromHrs = double.tryParse(_fromCtrl.text.trim());
    final toHrs = _openEnded ? null : double.tryParse(_toCtrl.text.trim());
    final fee = double.tryParse(_feeCtrl.text.trim());
    final order = int.tryParse(_orderCtrl.text.trim()) ?? 0;

    if (fromHrs == null || fromHrs < 0) {
      setState(() => _error = 'Enter a valid "From" value (≥ 0).');
      return;
    }
    if (!_openEnded && (toHrs == null || toHrs <= fromHrs)) {
      setState(() => _error = '"To" must be greater than "From".');
      return;
    }
    if (fee == null || fee < 0) {
      setState(() => _error = 'Enter a valid fee (≥ 0, use 0 for free).');
      return;
    }

    final fromMinutes = (fromHrs * 60).round();
    final toMinutes = toHrs != null ? (toHrs * 60).round() : null;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = CancellationPolicyRepository(Supabase.instance.client);
      await repo.upsertSlab(
        policyId: widget.policyId,
        id: widget.existing?.id,
        fromMinutes: fromMinutes,
        toMinutes: toMinutes,
        feeAmount: fee,
        label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
        sortOrder: order,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _timeDimensionHint => widget.policyType == 'before_assignment'
      ? 'hours elapsed since booking was placed'
      : 'hours remaining until scheduled service';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.existing == null ? 'Add Slab' : 'Edit Slab',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Time dimension: $_timeDimensionHint',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _fromCtrl,
                    decoration: const InputDecoration(
                      labelText: 'From (hours)',
                      hintText: '0',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'hrs',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _toCtrl,
                    enabled: !_openEnded,
                    decoration: const InputDecoration(
                      labelText: 'To (hours)',
                      hintText: 'e.g. 2',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'hrs',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Open-ended (no upper limit)',
                    style: TextStyle(fontSize: 13)),
                value: _openEnded,
                onChanged: (v) =>
                    setState(() => _openEnded = v ?? false),
                activeColor: AppColors.primary,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _feeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fee Amount',
                  hintText: '0 for free',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixText: '₹ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. "Free within 30 min"',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _orderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sort Order',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
