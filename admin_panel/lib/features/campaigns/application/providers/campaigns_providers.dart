import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/campaigns_repository.dart';
import '../../domain/models/campaign.dart';

final campaignsRepositoryProvider = Provider<CampaignsRepository>((ref) {
  return CampaignsRepository(ref.watch(supabaseClientProvider));
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class CampaignsNotifier extends StateNotifier<AsyncValue<List<Campaign>>> {
  final CampaignsRepository _repo;

  CampaignsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchCampaigns);
  }

  Future<void> refresh() => _load();

  Future<String> createCampaign({
    required String name,
    required String channel,
    required String message,
    required String templateId,
    required String templateLanguage,
    required String targetingType,
    String? targetingValue,
    String? targetingLabel,
    required bool isTestMode,
    int? estimatedCount,
  }) async {
    final id = await _repo.createCampaign(
      name: name,
      channel: channel,
      message: message,
      templateId: templateId,
      templateLanguage: templateLanguage,
      targetingType: targetingType,
      targetingValue: targetingValue,
      targetingLabel: targetingLabel,
      isTestMode: isTestMode,
      estimatedCount: estimatedCount,
    );
    await _load();
    return id;
  }

  Future<Map<String, dynamic>> sendSmsCampaign(String campaignId) async {
    final result = await _repo.sendSmsCampaign(campaignId);
    await _load();
    return result;
  }

  Future<void> resetTodrft(String campaignId) async {
    await _repo.resetTodrft(campaignId);
    await _load();
  }

  Future<void> deleteCampaign(String campaignId) async {
    await _repo.deleteCampaign(campaignId);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.where((c) => c.id != campaignId).toList(),
      );
    }
  }

  // Called by Realtime stream to patch a single campaign in-place
  void applyRealtimeUpdate(Map<String, dynamic> record) {
    final id = record['id'] as String?;
    if (id == null) return;
    final current = state.valueOrNull;
    if (current == null) { _load(); return; }
    final idx = current.indexWhere((c) => c.id == id);
    if (idx == -1) { _load(); return; }
    final updated = Campaign.fromMap(record);
    final newList = List<Campaign>.from(current);
    newList[idx] = updated;
    state = AsyncValue.data(newList);
  }
}

final campaignsNotifierProvider = StateNotifierProvider<
    CampaignsNotifier, AsyncValue<List<Campaign>>>((ref) {
  return CampaignsNotifier(ref.watch(campaignsRepositoryProvider));
});

// ── Realtime stream ───────────────────────────────────────────────────────────
// Watches for campaign status changes (draft → sending → sent/failed)
// so the UI reflects live progress without polling.

final campaignsRealtimeProvider = StreamProvider<void>((ref) {
  final notifier = ref.read(campaignsNotifierProvider.notifier);
  return Supabase.instance.client
      .from('campaigns')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) {
        // Update the notifier's in-memory state from Realtime events
        for (final row in rows) {
          notifier.applyRealtimeUpdate(row);
        }
      });
});
