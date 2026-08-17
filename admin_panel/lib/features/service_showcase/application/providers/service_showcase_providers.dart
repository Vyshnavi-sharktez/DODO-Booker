import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/service_showcase_repository.dart';

final serviceShowcaseRepositoryProvider =
    Provider<ServiceShowcaseRepository>((ref) {
  return ServiceShowcaseRepository(ref.watch(supabaseClientProvider));
});

class ServiceShowcaseNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final ServiceShowcaseRepository _repo;
  final String _nodeId;

  ServiceShowcaseNotifier(this._repo, this._nodeId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state =
        await AsyncValue.guard(() => _repo.fetchShowcasedImages(_nodeId));
  }

  Future<void> add(List<String> imageIds) async {
    await _repo.addToShowcase(_nodeId, imageIds);
    await _load();
  }

  Future<void> remove(String bookingImageId) async {
    await _repo.removeFromShowcase(_nodeId, bookingImageId);
    await _load();
  }
}

final serviceShowcaseNotifierProvider = StateNotifierProvider.family<
    ServiceShowcaseNotifier,
    AsyncValue<List<Map<String, dynamic>>>,
    String>(
  (ref, nodeId) => ServiceShowcaseNotifier(
    ref.watch(serviceShowcaseRepositoryProvider),
    nodeId,
  ),
);

/// All booking images available for this service (for the admin picker).
final availableBookingImagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
  (ref, nodeId) =>
      ref.watch(serviceShowcaseRepositoryProvider).fetchAvailableImages(nodeId),
);
