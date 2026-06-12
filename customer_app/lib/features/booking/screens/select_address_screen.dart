import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/address_model.dart';
import '../../../features/address/modals/address_form_modal.dart';
import '../services/booking_providers.dart';
import '../widgets/address_card.dart';

class SelectAddressScreen extends ConsumerStatefulWidget {
  final AddressModel? selectedAddress;
  final ValueChanged<AddressModel> onAddressSelected;

  const SelectAddressScreen({
    super.key,
    required this.selectedAddress,
    required this.onAddressSelected,
  });

  @override
  ConsumerState<SelectAddressScreen> createState() =>
      _SelectAddressScreenState();
}

class _SelectAddressScreenState extends ConsumerState<SelectAddressScreen> {
  Future<void> _addNewAddress() async {
    final newAddress = await AppModalDialog.show<AddressModel>(
      context: context,
      child: const AddressFormModal(),
    );
    if (!mounted || newAddress == null) return;
    widget.onAddressSelected(newAddress);
  }

  @override
  Widget build(BuildContext context) {
    final asyncAddresses = ref.watch(addressesProvider);

    return asyncAddresses.when(
      loading: () => const _AddressSkeleton(),
      error: (e, _) => _AddressError(
        onRetry: () =>
            ref.read(addressNotifierProvider.notifier).load(),
      ),
      data: (addresses) => _AddressList(
        addresses: addresses,
        selectedAddress: widget.selectedAddress ??
            (addresses.isNotEmpty
                ? addresses.firstWhere(
                    (a) => a.isDefault,
                    orElse: () => addresses.first,
                  )
                : null),
        onAddressSelected: widget.onAddressSelected,
        onAddNew: _addNewAddress,
      ),
    );
  }
}

// ── List ──────────────────────────────────────────────────────────────────────

class _AddressList extends StatelessWidget {
  final List<AddressModel> addresses;
  final AddressModel? selectedAddress;
  final ValueChanged<AddressModel> onAddressSelected;
  final VoidCallback onAddNew;

  const _AddressList({
    required this.addresses,
    required this.selectedAddress,
    required this.onAddressSelected,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        if (addresses.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Where should we come?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          ...addresses.map((addr) => AddressCard(
                address: addr,
                isSelected: selectedAddress?.id == addr.id,
                onTap: () => onAddressSelected(addr),
              )),
        ] else ...[
          const SizedBox(height: 40),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off_rounded,
                    size: 42, color: AppColors.textHint),
                SizedBox(height: 12),
                Text('No saved addresses'),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 8),
        _AddNewButton(onTap: onAddNew),
      ],
    );
  }
}

class _AddNewButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddNewButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add New Address'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class _AddressSkeleton extends StatelessWidget {
  const _AddressSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (ctx, idx) => Container(
        height: 120,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _AddressError extends StatelessWidget {
  final VoidCallback onRetry;

  const _AddressError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          const Text('Could not load addresses'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
