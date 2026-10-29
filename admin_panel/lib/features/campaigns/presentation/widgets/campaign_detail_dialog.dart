import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/campaigns_providers.dart';
import '../../domain/models/campaign.dart';

class CampaignDetailDialog extends ConsumerWidget {
  const CampaignDetailDialog({super.key, required this.campaign});
  final Campaign campaign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusBadge(),
                    const SizedBox(height: 20),
                    _buildSection('Campaign Details', [
                      _row('Name', campaign.name),
                      _row('Channel', 'SMS'),
                      _row('Template ID', campaign.templateId.isEmpty ? '—' : campaign.templateId),
                      _row('Mode', campaign.isTestMode ? 'Test mode' : 'Live'),
                      _row('Audience', _audienceLabel()),
                      if (campaign.createdAt != null)
                        _row('Created', DateFormat('dd MMM yyyy, hh:mm a').format(campaign.createdAt!.toLocal())),
                      if (campaign.sentAt != null)
                        _row('Sent at', DateFormat('dd MMM yyyy, hh:mm a').format(campaign.sentAt!.toLocal())),
                    ]),
                    if (campaign.message.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSection('Message Preview', [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(campaign.message,
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        ),
                      ]),
                    ],
                    if (campaign.isSent || campaign.isFailed) ...[
                      const SizedBox(height: 16),
                      _buildDeliveryStats(),
                    ],
                    if (campaign.failureSummary != null && campaign.failureSummary!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildFailureSummary(),
                    ],
                    if (campaign.isSent || campaign.isFailed) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Submitted count = messages accepted by MSG91, not confirmed delivered to handsets.',
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (campaign.canReset) ...[
                      const SizedBox(height: 20),
                      _buildResetButton(context, ref),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sms_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(campaign.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final (color, label) = switch (campaign.status) {
      'sent' => (AppColors.success, 'Sent'),
      'failed' => (AppColors.error, 'Failed'),
      'sending' => (AppColors.warning, 'Sending…'),
      'cancelled' => (AppColors.textSecondary, 'Cancelled'),
      _ => (AppColors.primary, 'Draft'),
    };
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (campaign.isSending)
                SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
        if (campaign.isTestMode) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Test',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ],
    );
  }

  Widget _buildDeliveryStats() {
    return _buildSection('Delivery Results', [
      _statRow('Recipients', campaign.recipientCount),
      _statRow('Submitted to MSG91', campaign.sentCount, color: AppColors.success),
      _statRow('Failed / Skipped', campaign.failedCount, color: campaign.failedCount > 0 ? AppColors.error : null),
    ]);
  }

  Widget _buildFailureSummary() {
    return _buildSection('Failure Details', [
      ...campaign.failureSummary!.take(20).map((entry) {
        final msg = entry['error'] as String? ?? entry['warning'] as String? ?? '—';
        final isWarning = entry.containsKey('warning');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isWarning ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
                size: 14,
                color: isWarning ? AppColors.warning : AppColors.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(msg,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
        );
      }),
    ]);
  }

  Widget _buildResetButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reset to Draft?'),
            content: const Text(
              'This will reset the campaign to draft status, clearing all delivery counts. '
              'You can then re-send it.\n\n'
              'Only use this if you are certain the previous send did not deliver any messages.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
                child: const Text('Reset'),
              ),
            ],
          ),
        );
        if (ok == true && context.mounted) {
          try {
            await ref.read(campaignsNotifierProvider.notifier).resetTodrft(campaign.id);
            if (context.mounted) Navigator.of(context).pop();
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Reset failed: $e'),
                backgroundColor: AppColors.error,
              ));
            }
          }
        }
      },
      icon: const Icon(Icons.restart_alt_rounded, size: 16),
      label: const Text('Reset to Draft'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.warning,
        side: const BorderSide(color: AppColors.warning),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, int value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _audienceLabel() {
    if (campaign.isTestMode) return 'Test phone only';
    return switch (campaign.targetingType) {
      'all' => 'All eligible customers',
      'city' => 'City: ${campaign.targetingLabel ?? campaign.targetingValue ?? '—'}',
      'booked_service' => 'Booked service: ${campaign.targetingLabel ?? '—'}',
      'booked_category' => 'Booked category: ${campaign.targetingLabel ?? '—'}',
      _ => campaign.targetingType,
    };
  }
}
