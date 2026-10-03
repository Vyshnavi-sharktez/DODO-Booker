import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/availability_block_repository.dart';
import '../../domain/models/availability_block.dart';

final availabilityBlockRepositoryProvider =
    Provider<AvailabilityBlockRepository>((ref) {
  return AvailabilityBlockRepository(ref.watch(supabaseClientProvider));
});

class AvailabilityBlocksNotifier
    extends StateNotifier<AsyncValue<List<AvailabilityBlock>>> {
  final AvailabilityBlockRepository _repo;

  AvailabilityBlocksNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAll);
  }

  Future<void> refresh() => _load();

  Future<void> create(AvailabilityBlock block) async {
    await _repo.create(block);
    await _load();
  }

  Future<void> update(AvailabilityBlock block) async {
    await _repo.update(block);
    await _load();
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((b) => b.id == id ? b.copyWith(isEnabled: enabled) : b)
            .toList(),
      );
    }
    try {
      await _repo.setEnabled(id, enabled: enabled);
    } catch (e) {
      await _load();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await _load();
  }
}

final availabilityBlocksNotifierProvider = StateNotifierProvider<
    AvailabilityBlocksNotifier, AsyncValue<List<AvailabilityBlock>>>((ref) {
  return AvailabilityBlocksNotifier(
    ref.watch(availabilityBlockRepositoryProvider),
  );
});
