import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/dodo_teams_repository.dart';
import '../../domain/models/dodo_team.dart';

final dodoTeamsRepositoryProvider = Provider<DodoTeamsRepository>((ref) {
  return DodoTeamsRepository(ref.watch(supabaseClientProvider));
});

class DodoTeamsNotifier extends StateNotifier<AsyncValue<List<DodoTeam>>> {
  final DodoTeamsRepository _repo;

  DodoTeamsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchDodoTeams);
  }

  Future<void> refresh() => _load();

  Future<void> createDodoTeam({
    required String teamName,
    String? supervisorName,
    String? phone,
    String? email,
    String? locality,
    required int membersCount,
    required String status,
  }) async {
    await _repo.createDodoTeam(
      teamName: teamName,
      supervisorName: supervisorName,
      phone: phone,
      email: email,
      locality: locality,
      membersCount: membersCount,
      status: status,
    );
    await _load();
  }

  Future<void> updateDodoTeam(
    String id, {
    required String teamName,
    String? supervisorName,
    String? phone,
    String? email,
    String? locality,
    required int membersCount,
    required String status,
  }) async {
    await _repo.updateDodoTeam(
      id,
      teamName: teamName,
      supervisorName: supervisorName,
      phone: phone,
      email: email,
      locality: locality,
      membersCount: membersCount,
      status: status,
    );
    await _load();
  }

  Future<void> deleteDodoTeam(String id) async {
    await _repo.deleteDodoTeam(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.where((t) => t.id != id).toList());
    }
  }
}

final dodoTeamsNotifierProvider =
    StateNotifierProvider<DodoTeamsNotifier, AsyncValue<List<DodoTeam>>>((ref) {
  return DodoTeamsNotifier(ref.watch(dodoTeamsRepositoryProvider));
});
