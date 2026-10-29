import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/campaigns_providers.dart';
import '../../domain/models/campaign.dart';
import '../widgets/create_campaign_dialog.dart';
import '../widgets/campaign_detail_dialog.dart';

class CampaignsPage extends ConsumerStatefulWidget {
  const CampaignsPage({super.key});

  @override
  ConsumerState<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends ConsumerState<CampaignsPage> {
  @override
  void initState() {
    super.initState();
    // Subscribe to Realtime updates so status changes propagate live
    ref.read(campaignsRealtimeProvider);
  }

  Future<void> _openCreate() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateCampaignDialog(),
    );
  }

  Future<void> _openDetail(Campaign c) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CampaignDetailDialog(campaign: c),
    );
  }

  Future<void> _confirmDelete(Campaign c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Campaign?'),
        content: Text('Delete "${c.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await ref.read(campaignsNotifierProvider.notifier).deleteCampaign(c.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaignsAsync = ref.watch(campaignsNotifierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          campaignsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorView(
              error: e.toString(),
              onRetry: () =>
                  ref.read(campaignsNotifierProvider.notifier).refresh(),
            ),
            data: (campaigns) => campaigns.isEmpty
                ? _EmptyState(onCreateTap: _openCreate)
                : _CampaignTable(
                    campaigns: campaigns,
                    onView: _openDetail,
                    onDelete: _confirmDelete,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.sms_rounded, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SMS Campaigns',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(
                'Send promotional SMS campaigns to customers via MSG91 Flow API',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New Campaign'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _CampaignTable extends StatelessWidget {
  const _CampaignTable({
    required this.campaigns,
    required this.onView,
    required this.onDelete,
  });

  final List<Campaign> campaigns;
  final void Function(Campaign) onView;
  final void Function(Campaign) onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          const Divider(height: 1, color: AppColors.border),
          ...campaigns.map(
            (c) => Column(children: [
              _CampaignRow(campaign: c, onView: onView, onDelete: onDelete),
              if (c != campaigns.last)
                const Divider(height: 1, color: AppColors.border),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    const style = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: const [
          Expanded(flex: 4, child: Text('CAMPAIGN', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          Expanded(flex: 2, child: Text('SUBMITTED', style: style)),
          Expanded(flex: 2, child: Text('AUDIENCE', style: style)),
          Expanded(flex: 2, child: Text('DATE', style: style)),
          SizedBox(width: 64, child: Text('', style: style)),
        ],
      ),
    );
  }
}

class _CampaignRow extends StatelessWidget {
  const _CampaignRow({
    required this.campaign,
    required this.onView,
    required this.onDelete,
  });

  final Campaign campaign;
  final void Function(Campaign) onView;
  final void Function(Campaign) onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onView(campaign),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Name + test badge
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Flexible(
                    child: Text(campaign.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (campaign.isTestMode) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('TEST',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              letterSpacing: 0.5)),
                    ),
                  ],
                ],
              ),
            ),
            // Status
            Expanded(flex: 2, child: _StatusChip(status: campaign.status)),
            // Submitted count
            Expanded(
              flex: 2,
              child: Text(
                campaign.isSent || campaign.isFailed
                    ? '${campaign.sentCount} / ${campaign.recipientCount}'
                    : '—',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
            // Audience
            Expanded(
              flex: 2,
              child: Text(
                _audienceShort(),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Date
            Expanded(
              flex: 2,
              child: Text(
                campaign.createdAt != null
                    ? DateFormat('dd MMM yy').format(campaign.createdAt!.toLocal())
                    : '—',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            // Actions
            SizedBox(
              width: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    onPressed: () => onView(campaign),
                    tooltip: 'View details',
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (campaign.canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      onPressed: () => onDelete(campaign),
                      tooltip: 'Delete',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.error,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _audienceShort() {
    if (campaign.isTestMode) return 'Test only';
    return switch (campaign.targetingType) {
      'all' => 'All customers',
      'city' => 'City: ${campaign.targetingLabel ?? '?'}',
      'booked_service' => 'By service',
      'booked_category' => 'By category',
      _ => campaign.targetingType,
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'sent' => (AppColors.success, 'Sent'),
      'failed' => (AppColors.error, 'Failed'),
      'sending' => (AppColors.warning, 'Sending'),
      'cancelled' => (AppColors.textSecondary, 'Cancelled'),
      _ => (AppColors.primary, 'Draft'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == 'sending')
          SizedBox(
            width: 8, height: 8,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        else
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateTap});
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_rounded, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('No campaigns yet',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Create your first SMS campaign to reach customers via MSG91.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Campaign'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 32, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            const Text('Failed to load campaigns',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
