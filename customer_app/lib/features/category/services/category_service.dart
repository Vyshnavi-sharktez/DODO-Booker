import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/addon_model.dart';
import '../../../models/category_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/service_model.dart';
import '../../../models/subcategory_model.dart';

class CategoryService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Categories (root catalog nodes) ───────────────────────────────────────

  Future<List<CategoryModel>> fetchCategories() async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchCategories → MOCK');
      return _devCategories;
    }
    debugPrint('[DODO][CategoryService] fetchCategories → catalog_nodes_view (is_root_node=true)');

    final data = await _db
        .from('catalog_nodes_view')
        .select()
        .eq('is_root_node', true)
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);

    return (data as List).map((row) {
      final r = row as Map<String, dynamic>;
      return CategoryModel(
        id: r['id'] as String,
        name: r['name'] as String,
        iconKey: r['icon_key'] as String?,
        imageUrl: r['image_url'] as String?,
        description: r['description'] as String?,
        isActive: (r['is_active'] as bool?) ?? true,
        subcategoryCount: (r['children_count'] as int?) ?? 0,
      );
    }).toList();
  }

  // ── Subcategories (direct children of a category node) ────────────────────

  Future<List<SubcategoryModel>> fetchSubcategoriesByCategoryId(
    String categoryId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchSubcategoriesByCategoryId($categoryId) → MOCK');
      return _devSubcategories
          .where((s) => s.categoryId == categoryId)
          .toList();
    }
    debugPrint('[DODO][CategoryService] fetchSubcategoriesByCategoryId($categoryId) → get_catalog_node_children');

    final data = await _db.rpc(
      'get_catalog_node_children',
      params: {'p_parent_id': categoryId},
    );

    return (data as List).map((row) {
      final r = row as Map<String, dynamic>;
      return SubcategoryModel(
        id: r['id'] as String,
        name: r['name'] as String,
        categoryId: categoryId,
        imageUrl: r['image_url'] as String?,
        description: r['description'] as String?,
        isActive: (r['is_active'] as bool?) ?? true,
        serviceCount: (r['children_count'] as int?) ?? 0,
      );
    }).toList();
  }

  // ── Services by subcategory (bookable children of a subcategory node) ──────

  Future<List<ServiceModel>> fetchServicesBySubcategoryId(
    String subcategoryId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchServicesBySubcategoryId($subcategoryId) → MOCK');
      return _devServices
          .where((s) => s.subcategoryId == subcategoryId)
          .toList();
    }
    debugPrint('[DODO][CategoryService] fetchServicesBySubcategoryId($subcategoryId) → catalog_nodes_view');

    final childData = await _db.rpc(
      'get_catalog_node_children',
      params: {'p_parent_id': subcategoryId},
    );

    final nodes = (childData as List)
        .map((e) => e as Map<String, dynamic>)
        .where((r) => (r['is_bookable'] as bool? ?? false) && (r['is_active'] as bool? ?? true))
        .toList();

    if (nodes.isEmpty) return [];

    final nodeIds = nodes.map((r) => r['id'] as String).toList();

    final faqData = await _db
        .from('service_faqs')
        .select()
        .inFilter('service_id', nodeIds)
        .order('sort_order', ascending: true);

    final addonData = await _db
        .from('addons')
        .select()
        .inFilter('service_id', nodeIds)
        .eq('is_active', true)
        .order('name', ascending: true);

    final faqsByNode = <String, List<Map<String, dynamic>>>{};
    for (final faq in (faqData as List)) {
      final sid = faq['service_id'] as String;
      faqsByNode.putIfAbsent(sid, () => []).add(faq as Map<String, dynamic>);
    }

    final addonsByNode = <String, List<Map<String, dynamic>>>{};
    for (final addon in (addonData as List)) {
      final sid = addon['service_id'] as String;
      addonsByNode.putIfAbsent(sid, () => []).add(addon as Map<String, dynamic>);
    }

    final results = nodes.map((r) {
      final nodeId = r['id'] as String;
      return ServiceModel.fromJson({
        ...r,
        'category_name': r['parent_name'],
        'service_faqs': faqsByNode[nodeId] ?? [],
        'addons': addonsByNode[nodeId] ?? [],
      });
    }).toList();

    debugPrint('[DODO][CategoryService] fetchServicesBySubcategoryId($subcategoryId) → ${results.length} node(s)');
    return results;
  }

  // ── Add-ons ────────────────────────────────────────────────────────────────

  Future<List<AddOnModel>> fetchAllActiveAddons() async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchAllActiveAddons → MOCK');
      return [];
    }
    debugPrint('[DODO][CategoryService] fetchAllActiveAddons → SUPABASE');
    final data = await _db
        .from('addons')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);
    return (data as List)
        .map((e) => AddOnModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AddOnModel>> fetchAddonsForService(String serviceId) async {
    if (!_ready) return [];
    final data = await _db
        .from('addons')
        .select()
        .eq('is_active', true)
        .eq('service_id', serviceId)
        .order('name', ascending: true);
    return (data as List)
        .map((e) => AddOnModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Service attributes ─────────────────────────────────────────────────────

  Future<List<ServiceAttributeModel>> fetchServiceAttributes(
    String serviceId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchServiceAttributes($serviceId) → MOCK');
      return _devAttributes
          .where((a) => a.serviceId == serviceId)
          .toList();
    }
    debugPrint('[DODO][CategoryService] fetchServiceAttributes($serviceId) → SUPABASE');

    const optionsSelect =
        'service_attribute_options(id, attribute_id, option_name, price_adjustment)';

    // service_id == catalog_node id for service-type nodes (UUIDs preserved).
    final data = await _db
        .from('service_attributes')
        .select('*, $optionsSelect')
        .eq('service_id', serviceId)
        .order('name', ascending: true);

    return (data as List)
        .map((e) => ServiceAttributeModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ── Dev dataset ───────────────────────────────────────────────────────────────
// IDs must stay aligned with HomeService._devCategories ('1'–'8').

final _devCategories = [
  const CategoryModel(id: '1', name: 'Cleaning',    subcategoryCount: 5, description: 'Professional home & commercial cleaning'),
  const CategoryModel(id: '2', name: 'Plumbing',    subcategoryCount: 5, description: 'Expert plumbing repairs and installations'),
  const CategoryModel(id: '3', name: 'Electrical',  subcategoryCount: 5, description: 'Safe and certified electrical services'),
  const CategoryModel(id: '4', name: 'Painting',    subcategoryCount: 4, description: 'Interior and exterior painting'),
  const CategoryModel(id: '5', name: 'Carpentry',   subcategoryCount: 4, description: 'Custom woodwork and furniture'),
  const CategoryModel(id: '6', name: 'Pest Control',subcategoryCount: 4, description: 'Safe and effective pest management'),
  const CategoryModel(id: '7', name: 'Appliances',  subcategoryCount: 5, description: 'Service and repair for all appliances'),
  const CategoryModel(id: '8', name: 'Shifting',    subcategoryCount: 4, description: 'Home and office relocation'),
];

final _devSubcategories = [
  // Cleaning (1)
  const SubcategoryModel(id: 's1',  name: 'Home Deep Clean',   categoryId: '1', description: 'Full home sanitization'),
  const SubcategoryModel(id: 's2',  name: 'Kitchen Cleaning',  categoryId: '1', description: 'Deep kitchen clean'),
  const SubcategoryModel(id: 's3',  name: 'Bathroom Cleaning', categoryId: '1', description: 'Tiles, fixtures, sanitization'),
  const SubcategoryModel(id: 's4',  name: 'Sofa & Carpet',     categoryId: '1', description: 'Upholstery steam cleaning'),
  const SubcategoryModel(id: 's5',  name: 'Office Cleaning',   categoryId: '1', description: 'Commercial workspace cleaning'),
  // Plumbing (2)
  const SubcategoryModel(id: 's6',  name: 'Tap & Faucet',      categoryId: '2', description: 'Repair and replacement'),
  const SubcategoryModel(id: 's7',  name: 'Pipe Repair',        categoryId: '2', description: 'Leak fix and pipe work'),
  const SubcategoryModel(id: 's8',  name: 'Drain Cleaning',     categoryId: '2', description: 'Blockage removal'),
  const SubcategoryModel(id: 's9',  name: 'Water Heater',       categoryId: '2', description: 'Geyser repair and install'),
  const SubcategoryModel(id: 's10', name: 'Toilet Repair',      categoryId: '2', description: 'Flush and seat repair'),
  // Electrical (3)
  const SubcategoryModel(id: 's11', name: 'Fan Installation',   categoryId: '3', description: 'Ceiling and exhaust fans'),
  const SubcategoryModel(id: 's12', name: 'Light Fitting',      categoryId: '3', description: 'Bulbs, fixtures, strips'),
  const SubcategoryModel(id: 's13', name: 'Wiring & MCB',       categoryId: '3', description: 'Wiring and circuit breakers'),
  const SubcategoryModel(id: 's14', name: 'Switch & Socket',    categoryId: '3', description: 'Replacement and repair'),
  const SubcategoryModel(id: 's15', name: 'Inverter Setup',     categoryId: '3', description: 'UPS and battery install'),
  // Painting (4)
  const SubcategoryModel(id: 's16', name: 'Wall Painting',      categoryId: '4', description: 'Interior emulsion painting'),
  const SubcategoryModel(id: 's17', name: 'Exterior Paint',     categoryId: '4', description: 'Weather-proof coatings'),
  const SubcategoryModel(id: 's18', name: 'Texture Painting',   categoryId: '4', description: 'Decorative wall finishes'),
  const SubcategoryModel(id: 's19', name: 'Wood Polish',        categoryId: '4', description: 'Furniture refinishing'),
  // Carpentry (5)
  const SubcategoryModel(id: 's20', name: 'Furniture Repair',   categoryId: '5', description: 'Fix and restore furniture'),
  const SubcategoryModel(id: 's21', name: 'Door & Window',      categoryId: '5', description: 'Frame and hinge repair'),
  const SubcategoryModel(id: 's22', name: 'Modular Kitchen',    categoryId: '5', description: 'Fitting and installation'),
  const SubcategoryModel(id: 's23', name: 'False Ceiling',      categoryId: '5', description: 'POP and gypsum work'),
  // Pest Control (6)
  const SubcategoryModel(id: 's24', name: 'Cockroach Control',  categoryId: '6', description: 'Gel bait treatment'),
  const SubcategoryModel(id: 's25', name: 'Termite Control',    categoryId: '6', description: 'Anti-termite treatment'),
  const SubcategoryModel(id: 's26', name: 'Bed Bug Treatment',  categoryId: '6', description: 'Heat and spray treatment'),
  const SubcategoryModel(id: 's27', name: 'Mosquito Control',   categoryId: '6', description: 'Fogging and larvicide'),
  // Appliances (7)
  const SubcategoryModel(id: 's28', name: 'AC Repair',          categoryId: '7', description: 'All brands serviced'),
  const SubcategoryModel(id: 's29', name: 'Washing Machine',    categoryId: '7', description: 'Repair and service'),
  const SubcategoryModel(id: 's30', name: 'Refrigerator',       categoryId: '7', description: 'Cooling and gas service'),
  const SubcategoryModel(id: 's31', name: 'Microwave Repair',   categoryId: '7', description: 'Repair and parts'),
  const SubcategoryModel(id: 's32', name: 'TV Repair',          categoryId: '7', description: 'All screen types'),
  // Shifting (8)
  const SubcategoryModel(id: 's33', name: 'Home Shifting',      categoryId: '8', description: 'Full relocation service'),
  const SubcategoryModel(id: 's34', name: 'Office Shifting',    categoryId: '8', description: 'Corporate relocation'),
  const SubcategoryModel(id: 's35', name: 'Vehicle Transport',  categoryId: '8', description: 'Two and four wheelers'),
  const SubcategoryModel(id: 's36', name: 'Storage',            categoryId: '8', description: 'Secure short-term storage'),
];

final _devServices = [
  const ServiceModel(id: 'svc_ac',  name: 'AC Repair',        subcategoryId: 's28', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'AC Repair',       startingPrice: 499),
  const ServiceModel(id: 'svc_wm',  name: 'Washing Machine',  subcategoryId: 's29', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'Washing Machine',  startingPrice: 799),
  const ServiceModel(id: 'svc_rf',  name: 'Refrigerator',     subcategoryId: 's30', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'Refrigerator',     startingPrice: 599),
  const ServiceModel(id: 'svc_hdc', name: 'Home Deep Clean',  subcategoryId: 's1',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Home Deep Clean',  startingPrice: 1299),
  const ServiceModel(id: 'svc_kc',  name: 'Kitchen Cleaning', subcategoryId: 's2',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Kitchen Cleaning', startingPrice: 699),
  const ServiceModel(id: 'svc_tf',  name: 'Tap & Faucet',     subcategoryId: 's6',  categoryId: '2', categoryName: 'Plumbing',   subcategoryName: 'Tap & Faucet',     startingPrice: 249),
  const ServiceModel(id: 'svc_fan', name: 'Fan Installation',  subcategoryId: 's11', categoryId: '3', categoryName: 'Electrical', subcategoryName: 'Fan Installation',  startingPrice: 299),
  const ServiceModel(id: 'svc_wp',  name: 'Wall Painting',    subcategoryId: 's16', categoryId: '4', categoryName: 'Painting',   subcategoryName: 'Wall Painting',    startingPrice: 1499),
];

final _devAttributes = <ServiceAttributeModel>[];
