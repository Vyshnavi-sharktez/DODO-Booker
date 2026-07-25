import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/providers/auth_provider.dart';
import '../../data/location_seo_repository.dart';
import '../../domain/models/location_node_seo.dart';

// ── Repository ─────────────────────────────────────────────────────────────────

final locationSeoRepositoryProvider = Provider<LocationSeoRepository>((ref) {
  return LocationSeoRepository(ref.watch(supabaseClientProvider));
});

// ── Pages for a specific area ──────────────────────────────────────────────────

/// Loads all location SEO configs for [areaId].
/// Invalidate after any upsert or delete to refresh the list.
final locationPagesForAreaProvider =
    FutureProvider.autoDispose.family<List<LocationNodeSeo>, String>(
  (ref, areaId) =>
      ref.watch(locationSeoRepositoryProvider).fetchForArea(areaId),
);
