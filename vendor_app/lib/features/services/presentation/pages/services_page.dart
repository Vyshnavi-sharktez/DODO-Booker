import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../providers/services_provider.dart';
import '../widgets/service_card.dart';

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(vendorServicesProvider);

    return VendorScaffold(
      title: 'My Services',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add Service',
          onPressed: () => _navigateToAdd(context, ref),
        ),
      ],
      child: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(vendorServicesProvider),
        ),
        data: (services) {
          if (services.isEmpty) {
            return EmptyStateView(
              icon: Icons.home_repair_service_outlined,
              title: 'No services yet',
              subtitle: 'Add the services you offer to start receiving bookings.',
              actionLabel: 'Add Service',
              action: () => _navigateToAdd(context, ref),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vendorServicesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: services.length,
              itemBuilder: (_, i) {
                final service = services[i];
                return ServiceCard(
                  service: service,
                  onToggle: (newValue) async {
                    await ref
                        .read(toggleServiceUseCaseProvider)
                        .call(service.id, newValue);
                    ref.invalidate(vendorServicesProvider);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _navigateToAdd(BuildContext context, WidgetRef ref) async {
    await context.push(RoutePaths.addService);
    ref.invalidate(vendorServicesProvider);
  }
}
