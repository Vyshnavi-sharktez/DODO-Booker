import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../service_faqs/presentation/widgets/custom_service_faqs_dialog.dart';
import '../../../service_scheduling/presentation/widgets/service_scheduling_dialog.dart';
import '../../../vendor_service_requests/data/vendor_service_requests_repository.dart';
import '../../../vendor_service_requests/domain/models/vendor_service_request.dart';
import '../../../vendor_service_requests/presentation/widgets/service_request_detail_dialog.dart';
import '../widgets/custom_service_config_dialog.dart';
import '../widgets/custom_service_edit_dialog.dart';
import '../widgets/custom_service_reviews_dialog.dart';
import '../widgets/custom_service_view_dialog.dart';

// ── Data ─────────────────────────────────────────────────────────────────────

class _CatalogEntry {
  const _CatalogEntry({required this.service, this.pendingEdit});
  final VendorServiceRequest service;
  final VendorServiceRequest? pendingEdit;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _vendorListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await Supabase.instance.client
      .from('vendors')
      .select('id, business_name')
      .eq('is_active', true)
      .order('business_name');
  return List<Map<String, dynamic>>.from(data as List);
});

final _selectedVendorIdProvider = StateProvider<String?>((ref) => null);

final _vendorCatalogProvider =
    FutureProvider.family<List<_CatalogEntry>, String>((ref, vendorId) async {
  final repo = VendorServiceRequestsRepository(Supabase.instance.client);
  final all = await repo.fetchByVendor(vendorId);
  final liveServices = all
      .where((r) => r.isNewService && (r.isCompleted || r.isPendingDeletion))
      .toList();
  final pendingEdits =
      all.where((r) => r.isEditService && r.isPending).toList();
  return liveServices.map((svc) {
    final edit = pendingEdits
        .where((e) => e.parentRequestId == svc.id)
        .firstOrNull;
    return _CatalogEntry(service: svc, pendingEdit: edit);
  }).toList();
});

// ── Page ─────────────────────────────────────────────────────────────────────

class VendorCatalogPage extends ConsumerStatefulWidget {
  const VendorCatalogPage({super.key});

  @override
  ConsumerState<VendorCatalogPage> createState() => _VendorCatalogPageState();
}

class _VendorCatalogPageState extends ConsumerState<VendorCatalogPage> {
  final _searchCtrl = TextEditingController();
  String _vendorSearch = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(_vendorListProvider);
    final selectedVendorId = ref.watch(_selectedVendorIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Vendor picker ──────────────────────────────────────────────────
          Container(
            width: 260,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                const _PanelHeader(title: 'Vendors'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search vendors…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onChanged: (v) => setState(() => _vendorSearch = v.trim()),
                  ),
                ),
                Expanded(
                  child: vendorsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Error: $e',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13)),
                    ),
                    data: (vendors) {
                      final filtered = _vendorSearch.isEmpty
                          ? vendors
                          : vendors
                              .where((v) => (v['business_name'] as String)
                                  .toLowerCase()
                                  .contains(_vendorSearch.toLowerCase()))
                              .toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text('No vendors found',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        );
                      }

                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final v = filtered[i];
                          final id = v['id'] as String;
                          final name = v['business_name'] as String;
                          final isSelected = id == selectedVendorId;

                          return ColoredBox(
                            color: isSelected
                                ? const Color(0xFF1E3A5F)
                                : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: isSelected
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : AppColors.border,
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              onTap: () => ref
                                  .read(_selectedVendorIdProvider.notifier)
                                  .state = id,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Service list ───────────────────────────────────────────────────
          Expanded(
            child: selectedVendorId == null
                ? const _EmptySelection()
                : _VendorServiceList(vendorId: selectedVendorId),
          ),
        ],
      ),
    );
  }
}

// ── Vendor service list ───────────────────────────────────────────────────────

class _VendorServiceList extends ConsumerWidget {
  const _VendorServiceList({required this.vendorId});
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncServices =
        ref.watch(_vendorCatalogProvider(vendorId));

    return asyncServices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load services',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(e.toString(),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(_vendorCatalogProvider(vendorId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (services) {
        if (services.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 16),
                Text('No active custom services',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary)),
                SizedBox(height: 4),
                Text(
                  'This vendor has no approved custom services yet.',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelHeader(title: 'Custom Services'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(_vendorCatalogProvider(vendorId)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: services.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ServiceCard(
                    service: services[i].service,
                    pendingEdit: services[i].pendingEdit,
                    onUpdated: () =>
                        ref.invalidate(_vendorCatalogProvider(vendorId)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends ConsumerStatefulWidget {
  const _ServiceCard({
    required this.service,
    required this.onUpdated,
    this.pendingEdit,
  });
  final VendorServiceRequest service;
  final VendorServiceRequest? pendingEdit;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends ConsumerState<_ServiceCard> {
  bool _toggling = false;

  Future<void> _toggleActive() async {
    if (_toggling) return;
    // Guard immediately so a second tap before the dialog opens is a no-op.
    setState(() => _toggling = true);
    final service = widget.service;
    final activate = !service.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activate ? 'Activate Service?' : 'Deactivate Service?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activate
                  ? 'Customers will be able to discover and book "${service.serviceName}".'
                  : 'Customers will no longer see "${service.serviceName}".',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: activate
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                    child: Text(activate ? 'Activate' : 'Deactivate'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // Reset spinner if user cancelled.
    if (confirmed != true) {
      if (mounted) setState(() => _toggling = false);
      return;
    }
    if (!mounted) return;
    try {
      final repo = VendorServiceRequestsRepository(Supabase.instance.client);
      await repo.toggleActive(service.id, isActive: activate);
      if (mounted) widget.onUpdated();
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

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final isPendingDeletion = service.isPendingDeletion;

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPendingDeletion
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Main info row ──────────────────────────────────────────────
          // Split into two independent tap zones:
          //   • InkWell (left/expanded) → opens ServiceRequestDetailDialog
          //   • Status badges (right, outside InkWell) → toggles is_active
          // Nesting a GestureDetector inside InkWell causes both onTap handlers
          // to fire in the same frame, hitting the navigator lock assertion.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Tappable info area ───────────────────────────────────
              Expanded(
                child: InkWell(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  onTap: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) =>
                          ServiceRequestDetailDialog(request: service),
                    );
                    widget.onUpdated();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (service.imageUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              service.imageUrl!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const _PlaceholderIcon(),
                            ),
                          ),
                          const SizedBox(width: 14),
                        ] else ...[
                          const _PlaceholderIcon(),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service.serviceName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (service.description != null &&
                                  service.description!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  service.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _PriceBadge(
                                    label: 'Price',
                                    price: service.formattedActivePrice,
                                    color: AppColors.textSecondary,
                                  ),
                                  if (service.price != service.activePrice &&
                                      service.price != null) ...[
                                    const SizedBox(width: 8),
                                    _PriceBadge(
                                      label: 'Original',
                                      price: service.formattedPrice,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(
                                    service.formattedDate,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Active/Inactive toggle (outside InkWell) ────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Switch(
                      value: service.isActive,
                      onChanged: _toggling ? null : (_) => _toggleActive(),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                    ),
                    Text(
                      service.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: service.isActive
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (isPendingDeletion) ...[
                      const SizedBox(height: 6),
                      const _DeletionPendingChip(),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // ── Pending edit bar ──────────────────────────────────────────
          if (widget.pendingEdit != null)
            _PendingEditBar(
              pendingEdit: widget.pendingEdit!,
              onAction: widget.onUpdated,
            ),

          // ── Action bar ────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                _ActionButton(
                  icon: Icons.preview_rounded,
                  label: 'View',
                  onTap: () => CustomServiceViewDialog.show(
                    context,
                    service: service,
                  ),
                ),
                const _ActionDivider(),
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () => CustomServiceEditDialog.show(
                    context,
                    service: service,
                    onSaved: widget.onUpdated,
                  ),
                ),
                const _ActionDivider(),
                _ActionButton(
                  icon: Icons.quiz_outlined,
                  label: 'FAQs',
                  onTap: () => CustomServiceFaqsDialog.show(
                    context,
                    customServiceId: service.id,
                    serviceName: service.serviceName,
                  ),
                ),
                const _ActionDivider(),
                _ActionButton(
                  icon: Icons.schedule_rounded,
                  label: 'Scheduling',
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => ServiceSchedulingDialog(
                      serviceId: service.id,
                      serviceName: service.serviceName,
                    ),
                  ),
                ),
                const _ActionDivider(),
                _ActionButton(
                  icon: Icons.star_outline_rounded,
                  label: 'Reviews',
                  onTap: () => CustomServiceReviewsDialog.show(
                    context,
                    customServiceId: service.id,
                    serviceName: service.serviceName,
                  ),
                ),
                const _ActionDivider(),
                _ActionButton(
                  icon: Icons.tune_rounded,
                  label: 'Config',
                  onTap: () => CustomServiceConfigDialog.show(
                    context,
                    customServiceId: service.id,
                    serviceName: service.serviceName,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending edit bar ──────────────────────────────────────────────────────────

class _PendingEditBar extends StatefulWidget {
  const _PendingEditBar({
    required this.pendingEdit,
    required this.onAction,
  });
  final VendorServiceRequest pendingEdit;
  final VoidCallback onAction;

  @override
  State<_PendingEditBar> createState() => _PendingEditBarState();
}

class _PendingEditBarState extends State<_PendingEditBar> {
  bool _actioning = false;

  Future<void> _approve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Changes?'),
        content: const Text(
            'The proposed edits will become live immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actioning = true);
    try {
      final repo =
          VendorServiceRequestsRepository(Supabase.instance.client);
      await repo.accept(widget.pendingEdit.id);
      if (mounted) widget.onAction();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _actioning = false);
      }
    }
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Changes'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Reason for rejection (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(reasonCtrl.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null || !mounted) return;
    setState(() => _actioning = true);
    try {
      final repo =
          VendorServiceRequestsRepository(Supabase.instance.client);
      await repo.reject(widget.pendingEdit.id, reason: reason);
      if (mounted) widget.onAction();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _actioning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBE6),
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFFFFD666)),
        ),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.pending_outlined,
              size: 15, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Vendor edit pending approval',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF92400E)),
            ),
          ),
          TextButton(
            onPressed: _actioning
                ? null
                : () => CustomServiceViewDialog.show(
                      context,
                      service: widget.pendingEdit,
                      isProposal: true,
                    ),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('View',
                style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          if (_actioning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            OutlinedButton(
              onPressed: _reject,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Reject',
                  style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _approve,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Approve',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      child: VerticalDivider(width: 1, color: AppColors.border),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.home_repair_service_outlined,
          color: AppColors.textSecondary, size: 24),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge(
      {required this.label, required this.price, required this.color});
  final String label;
  final String price;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $price',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DeletionPendingChip extends StatelessWidget {
  const _DeletionPendingChip();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'Deletion Pending',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 56, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'Select a vendor',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Choose a vendor from the left panel to view their custom services.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
