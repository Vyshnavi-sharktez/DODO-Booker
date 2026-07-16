import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/serving_areas_datasource.dart';
import '../../domain/models/serving_area.dart';

final _datasource = ServingAreasDatasource(Supabase.instance.client);

final activeServingAreasProvider = FutureProvider<List<ServingArea>>((ref) {
  return _datasource.fetchActive();
});

final vendorAssignedAreaIdsProvider =
    FutureProvider.family<List<String>, String>((ref, vendorId) {
  return _datasource.fetchAssignedIds(vendorId);
});

final servingAreasDatasourceProvider =
    Provider<ServingAreasDatasource>((_) => _datasource);
