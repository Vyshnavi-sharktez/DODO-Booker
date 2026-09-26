import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/address_model.dart';
import '../modals/address_form_modal.dart';
import '../services/address_providers.dart';

class AddressScreen extends ConsumerWidget {
  final bool inModal;
  // When true (opened from Checkout), each card shows a "Select" button
  // that pops the sheet with the chosen AddressModel. All management
  // actions (edit, delete, set-default) remain fully available.
  final bool pickMode;
  const AddressScreen({super.key, this.inModal = false, this.pickMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final asyncAddresses = ref.watch(addressNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: inModal
          ? null
          : AppBar(
              title: Text(
                pickMode ? 'Select Address' : 'My Addresses',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: cs.outline.withAlpha(60)),
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
                onSetDefault: (addr) =>
                    ref.read(addressNotifierProvider.notifier).setDefault(addr.id),
                onPick: pickMode ? (addr) => Navigator.of(context).pop(addr) : null,
              ),
      ),
      floatingActionButton: asyncAddresses.maybeWhen(
        data: (addresses) => addresses.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: () => _openAddForm(context, ref),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Address'),
                backgroundColor: cs.primary,
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
  final ValueChanged<AddressModel>? onEdit;
  final ValueChanged<AddressModel>? onDelete;
  final ValueChanged<AddressModel>? onSetDefault;
  // Non-null when opened from Checkout — pops the sheet with the chosen address.
  final ValueChanged<AddressModel>? onPick;

  const _AddressList({
    required this.addresses,
    required this.onAdd,
    this.onEdit,
    this.onDelete,
    this.onSetDefault,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: addresses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AddressManageCard(
        address: addresses[i],
        onEdit: onEdit != null ? () => onEdit!(addresses[i]) : null,
        onDelete: onDelete != null ? () => onDelete!(addresses[i]) : null,
        onSetDefault: onSetDefault != null ? () => onSetDefault!(addresses[i]) : null,
        onPick: onPick != null ? () => onPick!(addresses[i]) : null,
      ),
    );
  }
}

// ── Manage card (screen only — edit/delete actions) ───────────────────────────

class _AddressManageCard extends StatelessWidget {
  final AddressModel address;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDefault;
  // Non-null when opened from Checkout: pops the sheet with this address.
  final VoidCallback? onPick;

  const _AddressManageCard({
    required this.address,
    this.onEdit,
    this.onDelete,
    this.onSetDefault,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withAlpha(80)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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

                    // Details (label + address lines only)
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 10,
                                        color: AppColors.success,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Default',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address.line1,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          if (address.line2 != null)
                            Text(
                              address.line2!,
                              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            '${address.city}, ${address.state} – ${address.pincode}',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),

                    // Edit / Delete actions
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

                // "Set as Default" pill button — only for non-default addresses
                if (onSetDefault != null && !address.isDefault) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: onSetDefault,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primary.withAlpha(120),
                        ),
                      ),
                      child: Text(
                        'Set as Default',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // "Select for this booking" footer — only shown in pick mode
          if (onPick != null) ...[
            Divider(height: 1, thickness: 1, color: cs.outline.withAlpha(60)),
            InkWell(
              onTap: onPick,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Select for this booking',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
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
    final cs = Theme.of(context).colorScheme;
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
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_off_rounded,
                size: 34,
                color: cs.onSurface.withAlpha(120),
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
                color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        height: 110,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.onSurface.withAlpha(20),
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: cs.onSurface.withAlpha(120)),
          const SizedBox(height: 12),
          const Text('Could not load addresses'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
