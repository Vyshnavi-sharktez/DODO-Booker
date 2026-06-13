import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/services_provider.dart';
import '../widgets/catalog_service_tile.dart';

class AddServicePage extends ConsumerStatefulWidget {
  const AddServicePage({super.key});

  @override
  ConsumerState<AddServicePage> createState() => _AddServicePageState();
}

class _AddServicePageState extends ConsumerState<AddServicePage> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogServicesProvider);
    final vendorServicesAsync = ref.watch(vendorServicesProvider);
    final assignState = ref.watch(assignServicesProvider);
    final isSaving = assignState.isLoading;

    ref.listen<AsyncValue<void>>(assignServicesProvider, (prev, next) {
      if (next is AsyncData && prev?.isLoading == true) {
        if (context.mounted) context.pop();
      } else if (next is AsyncError) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add services: ${next.error}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    });

    final alreadyAssignedIds =
        vendorServicesAsync.valueOrNull?.map((s) => s.serviceId).toSet() ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Services'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(catalogServicesProvider),
        ),
        data: (catalog) {
          if (catalog.isEmpty) {
            return const Center(
              child: Text('No services available in the catalog.'),
            );
          }
          return AbsorbPointer(
            absorbing: isSaving,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: catalog.length,
              itemBuilder: (_, i) {
                final service = catalog[i];
                final isAssigned = alreadyAssignedIds.contains(service.id);
                return CatalogServiceTile(
                  service: service,
                  selected: _selected.contains(service.id),
                  alreadyAssigned: isAssigned,
                  onTap: () {
                    setState(() {
                      if (_selected.contains(service.id)) {
                        _selected.remove(service.id);
                      } else {
                        _selected.add(service.id);
                      }
                    });
                  },
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: isSaving ? null : _assign,
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(
                    isSaving
                        ? 'Adding…'
                        : 'Add ${_selected.length} '
                            'Service${_selected.length > 1 ? 's' : ''}',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ),
    );
  }

  void _assign() {
    final user = ref.read(currentVendorUserProvider);
    if (user == null) return;
    ref
        .read(assignServicesProvider.notifier)
        .assign(user.id, _selected.toList());
  }
}
