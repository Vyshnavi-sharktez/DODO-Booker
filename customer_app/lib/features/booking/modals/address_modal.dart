import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/address_model.dart';
import '../../../features/address/modals/address_form_modal.dart';
import '../services/booking_providers.dart';
import '../widgets/address_card.dart';

/// Address selection modal used in the booking flow.
/// Pops with the selected [AddressModel] or null.
class AddressModal extends ConsumerStatefulWidget {
  const AddressModal({super.key});

  @override
  ConsumerState<AddressModal> createState() => _AddressModalState();
}

class _AddressModalState extends ConsumerState<AddressModal> {
  AddressModel? _selected;

  Future<void> _addNewAddress() async {
    final newAddress = await AppModalDialog.show<AddressModel>(
      context: context,
      child: const AddressFormModal(),
    );
    if (!mounted || newAddress == null) return;
    // Auto-select the newly added address.
    setState(() => _selected = newAddress);
  }

  @override
  Widget build(BuildContext context) {
    final asyncAddresses = ref.watch(addressesProvider);

    return AppModalDialog(
      title: 'Select Address',
      subtitle: const Text('Where should we come?'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          asyncAddresses.when(
            loading: () => const _AddressSkeleton(),
            error: (e, _) => _AddressError(
              onRetry: () =>
                  ref.read(addressNotifierProvider.notifier).load(),
            ),
            data: (addresses) => addresses.isEmpty
                ? _NoAddressState(onAdd: _addNewAddress)
                : _AddressList(
                    addresses: addresses,
                    selected: _selected ??
                        addresses.firstWhere(
                          (a) => a.isDefault,
                          orElse: () => addresses.first,
                        ),
                    onSelect: (addr) => setState(() => _selected = addr),
                  ),
          ),
          const SizedBox(height: 12),

          // "Add New Address" button — always shown when list is non-empty
          asyncAddresses.maybeWhen(
            data: (addresses) => addresses.isNotEmpty
                ? OutlinedButton.icon(
                    onPressed: _addNewAddress,
                    icon: const Icon(Icons.add_location_alt_rounded),
                    label: const Text('Add New Address'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),

          const SizedBox(height: 12),

          // Confirm button — disabled when no address is selected
          FilledButton(
            onPressed: asyncAddresses.maybeWhen(
              data: (addresses) {
                final effective = _selected ??
                    (addresses.isNotEmpty
                        ? addresses.firstWhere(
                            (a) => a.isDefault,
                            orElse: () => addresses.first,
                          )
                        : null);
                return effective != null
                    ? () => Navigator.of(context).pop(effective)
                    : null;
              },
              orElse: () => null,
            ),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: const Text(
              'Confirm Address',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Address list ──────────────────────────────────────────────────────────────

class _AddressList extends StatelessWidget {
  final List<AddressModel> addresses;
  final AddressModel selected;
  final ValueChanged<AddressModel> onSelect;

  const _AddressList({
    required this.addresses,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: addresses
          .map((a) => AddressCard(
                address: a,
                isSelected: selected.id == a.id,
                onTap: () => onSelect(a),
              ))
          .toList(),
    );
  }
}

// ── No address state (force-add before booking) ───────────────────────────────

class _NoAddressState extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoAddressState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_off_rounded,
            size: 42,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            'No saved addresses',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Add an address to continue booking.',
            style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text('Add Address'),
            style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _AddressSkeleton extends StatelessWidget {
  const _AddressSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          height: 90,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _AddressError extends StatelessWidget {
  final VoidCallback onRetry;
  const _AddressError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: 10),
          const Text('Could not load addresses'),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
