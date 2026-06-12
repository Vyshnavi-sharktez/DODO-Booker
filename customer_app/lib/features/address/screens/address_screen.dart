import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/address_model.dart';
import '../modals/address_form_modal.dart';
import '../services/address_providers.dart';

class AddressScreen extends ConsumerWidget {
  const AddressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAddresses = ref.watch(addressNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Addresses',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: asyncAddresses.when(
        loading: () => const _AddressSkeleton(),
        error: (e, _) => _AddressErrorState(
          onRetry: () => ref.read(addressNotifierProvider.notifier).load(),
        ),
        data: (addresses) => addresses.isEmpty
            ? _EmptyAddressState(onAdd: () => _openAddForm(context, ref))
            : _AddressList(
                addresses: addresses,
                onAdd: () => _openAddForm(context, ref),
                onEdit: (addr) => _openEditForm(context, ref, addr),
                onDelete: (addr) => _confirmDelete(context, ref, addr),
              ),
      ),
      floatingActionButton: asyncAddresses.maybeWhen(
        data: (addresses) => addresses.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: () => _openAddForm(context, ref),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Address'),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              )
            : null,
        orElse: () => null,
      ),
    );
  }

  Future<void> _openAddForm(BuildContext context, WidgetRef ref) async {
    await AppModalDialog.show<AddressModel>(
      context: context,
      child: const AddressFormModal(),
    );
  }

  Future<void> _openEditForm(
    BuildContext context,
    WidgetRef ref,
    AddressModel address,
  ) async {
    await AppModalDialog.show<AddressModel>(
      context: context,
      child: AddressFormModal(initialAddress: address),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AddressModel address,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text(
          'Remove "${address.label}" at ${address.line1}, ${address.city}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    try {
      await ref.read(addressNotifierProvider.notifier).delete(address.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Address list ──────────────────────────────────────────────────────────────

class _AddressList extends StatelessWidget {
  final List<AddressModel> addresses;
  final VoidCallback onAdd;
  final ValueChanged<AddressModel> onEdit;
  final ValueChanged<AddressModel> onDelete;

  const _AddressList({
    required this.addresses,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: addresses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AddressManageCard(
        address: addresses[i],
        onEdit: () => onEdit(addresses[i]),
        onDelete: () => onDelete(addresses[i]),
      ),
    );
  }
}

// ── Manage card (screen only — edit/delete actions) ───────────────────────────

class _AddressManageCard extends StatelessWidget {
  final AddressModel address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressManageCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconForLabel(address.label),
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        address.label,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withAlpha(25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.success.withAlpha(80)),
                          ),
                          child: const Text(
                            'Default',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.line1,
                    style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                  if (address.line2 != null)
                    Text(
                      address.line2!,
                      style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${address.city}, ${address.state} – ${address.pincode}',
                    style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
      case 'office':
        return Icons.work_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyAddressState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyAddressState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                size: 34,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No saved addresses',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first address to use\nduring bookings.',
              style: tt.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text(
                'Add Address',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _AddressSkeleton extends StatelessWidget {
  const _AddressSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        height: 110,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _AddressErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _AddressErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          const Text('Could not load addresses'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
