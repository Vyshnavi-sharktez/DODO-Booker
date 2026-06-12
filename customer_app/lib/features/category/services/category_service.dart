import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/category_model.dart';
import '../../../models/subcategory_model.dart';

class CategoryService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Categories ─────────────────────────────────────────────────────────────

  Future<List<CategoryModel>> fetchCategories() async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchCategories → MOCK (Supabase not configured)');
      return _devCategories;
    }
    debugPrint('[DODO][CategoryService] fetchCategories → SUPABASE (table: categories)');

    final data = await _db
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return (data as List)
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Subcategories ──────────────────────────────────────────────────────────
  //
  // Table: sub_categories (FK: category_id → categories.id)

  Future<List<SubcategoryModel>> fetchSubcategoriesByCategoryId(
    String categoryId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][CategoryService] fetchSubcategoriesByCategoryId($categoryId) → MOCK (Supabase not configured)');
      return _devSubcategories
          .where((s) => s.categoryId == categoryId)
          .toList();
    }
    debugPrint('[DODO][CategoryService] fetchSubcategoriesByCategoryId($categoryId) → SUPABASE (table: sub_categories)');

    final data = await _db
        .from('sub_categories')
        .select()
        .eq('category_id', categoryId)
        .eq('is_active', true)
        .order('name', ascending: true);

    return (data as List)
        .map((e) => SubcategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ── Dev fallback dataset ──────────────────────────────────────────────────────

final _devCategories = [
  const CategoryModel(id: '1', name: 'Cleaning', description: 'Professional home & commercial cleaning'),
  const CategoryModel(id: '2', name: 'Plumbing', description: 'Expert plumbing repairs and installations'),
  const CategoryModel(id: '3', name: 'Electrical', description: 'Safe and certified electrical services'),
  const CategoryModel(id: '4', name: 'Painting', description: 'Interior and exterior painting'),
  const CategoryModel(id: '5', name: 'Carpentry', description: 'Custom woodwork and furniture'),
  const CategoryModel(id: '6', name: 'Pest Control', description: 'Safe and effective pest management'),
  const CategoryModel(id: '7', name: 'Appliances', description: 'Service and repair for all appliances'),
  const CategoryModel(id: '8', name: 'Shifting', description: 'Home and office relocation'),
];

final _devSubcategories = [
  // Cleaning
  const SubcategoryModel(id: 's1', name: 'Home Deep Clean', categoryId: '1', description: 'Full home sanitization'),
  const SubcategoryModel(id: 's2', name: 'Kitchen Cleaning', categoryId: '1', description: 'Deep kitchen clean'),
  const SubcategoryModel(id: 's3', name: 'Bathroom Cleaning', categoryId: '1', description: 'Tiles, fixtures, sanitization'),
  const SubcategoryModel(id: 's4', name: 'Sofa & Carpet', categoryId: '1', description: 'Upholstery steam cleaning'),
  const SubcategoryModel(id: 's5', name: 'Office Cleaning', categoryId: '1', description: 'Commercial workspace cleaning'),
  // Plumbing
  const SubcategoryModel(id: 's6', name: 'Tap & Faucet', categoryId: '2', description: 'Repair and replacement'),
  const SubcategoryModel(id: 's7', name: 'Pipe Repair', categoryId: '2', description: 'Leak fix and pipe work'),
  const SubcategoryModel(id: 's8', name: 'Drain Cleaning', categoryId: '2', description: 'Blockage removal'),
  const SubcategoryModel(id: 's9', name: 'Water Heater', categoryId: '2', description: 'Geyser repair and install'),
  const SubcategoryModel(id: 's10', name: 'Toilet Repair', categoryId: '2', description: 'Flush and seat repair'),
  // Electrical
  const SubcategoryModel(id: 's11', name: 'Fan Installation', categoryId: '3', description: 'Ceiling and exhaust fans'),
  const SubcategoryModel(id: 's12', name: 'Light Fitting', categoryId: '3', description: 'Bulbs, fixtures, strips'),
  const SubcategoryModel(id: 's13', name: 'Wiring & MCB', categoryId: '3', description: 'Wiring and circuit breakers'),
  const SubcategoryModel(id: 's14', name: 'Switch & Socket', categoryId: '3', description: 'Replacement and repair'),
  const SubcategoryModel(id: 's15', name: 'Inverter Setup', categoryId: '3', description: 'UPS and battery install'),
  // Painting
  const SubcategoryModel(id: 's16', name: 'Wall Painting', categoryId: '4', description: 'Interior emulsion painting'),
  const SubcategoryModel(id: 's17', name: 'Exterior Paint', categoryId: '4', description: 'Weather-proof coatings'),
  const SubcategoryModel(id: 's18', name: 'Texture Painting', categoryId: '4', description: 'Decorative wall finishes'),
  const SubcategoryModel(id: 's19', name: 'Wood Polish', categoryId: '4', description: 'Furniture refinishing'),
  // Carpentry
  const SubcategoryModel(id: 's20', name: 'Furniture Repair', categoryId: '5', description: 'Fix and restore furniture'),
  const SubcategoryModel(id: 's21', name: 'Door & Window', categoryId: '5', description: 'Frame and hinge repair'),
  const SubcategoryModel(id: 's22', name: 'Modular Kitchen', categoryId: '5', description: 'Fitting and installation'),
  const SubcategoryModel(id: 's23', name: 'False Ceiling', categoryId: '5', description: 'POP and gypsum work'),
  // Pest Control
  const SubcategoryModel(id: 's24', name: 'Cockroach Control', categoryId: '6', description: 'Gel bait treatment'),
  const SubcategoryModel(id: 's25', name: 'Termite Control', categoryId: '6', description: 'Anti-termite treatment'),
  const SubcategoryModel(id: 's26', name: 'Bed Bug Treatment', categoryId: '6', description: 'Heat and spray treatment'),
  const SubcategoryModel(id: 's27', name: 'Mosquito Control', categoryId: '6', description: 'Fogging and larvicide'),
  // Appliances
  const SubcategoryModel(id: 's28', name: 'AC Service', categoryId: '7', description: 'All brands serviced'),
  const SubcategoryModel(id: 's29', name: 'Washing Machine', categoryId: '7', description: 'Repair and service'),
  const SubcategoryModel(id: 's30', name: 'Refrigerator', categoryId: '7', description: 'Cooling and gas service'),
  const SubcategoryModel(id: 's31', name: 'Microwave', categoryId: '7', description: 'Repair and parts'),
  const SubcategoryModel(id: 's32', name: 'TV Repair', categoryId: '7', description: 'All screen types'),
  // Shifting
  const SubcategoryModel(id: 's33', name: 'Home Shifting', categoryId: '8', description: 'Full relocation service'),
  const SubcategoryModel(id: 's34', name: 'Office Shifting', categoryId: '8', description: 'Corporate relocation'),
  const SubcategoryModel(id: 's35', name: 'Vehicle Transport', categoryId: '8', description: 'Two and four wheelers'),
  const SubcategoryModel(id: 's36', name: 'Storage', categoryId: '8', description: 'Secure short-term storage'),
];
