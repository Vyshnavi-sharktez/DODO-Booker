import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/vendor_root_categories_repository.dart';
import '../../domain/models/vendor_root_category.dart';

final _repoProvider = Provider<VendorRootCategoriesRepository>(
  (ref) => VendorRootCategoriesRepository(Supabase.instance.client),
);

final vendorRootCategoriesProvider =
    AsyncNotifierProvider<VendorRootCategoriesNotifier, List<VendorRootCategory>>(
  VendorRootCategoriesNotifier.new,
);

class VendorRootCategoriesNotifier
    extends AsyncNotifier<List<VendorRootCategory>> {
  VendorRootCategoriesRepository get _repo => ref.read(_repoProvider);

  @override
  Future<List<VendorRootCategory>> build() => _repo.fetchAll();

  Future<void> create({
    required String name,
    String? iconUrl,
    int sortOrder = 0,
  }) async {
    await _repo.create(name: name, iconUrl: iconUrl, sortOrder: sortOrder);
    ref.invalidateSelf();
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    String? iconUrl,
    int sortOrder = 0,
  }) async {
    await _repo.update(id: id, name: name, iconUrl: iconUrl, sortOrder: sortOrder);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    ref.invalidateSelf();
  }
}
