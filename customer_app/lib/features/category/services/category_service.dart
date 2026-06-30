import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/category_model.dart';
import '../../../models/service_attribute_model.dart';
import '../../../models/service_model.dart';
import '../../../models/subcategory_model.dart';

class CategoryService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Categories ─────────────────────────────────────────────────────────────

  Future<List<CategoryModel>> fetchCategories() async {
    if (!_ready) {
      debugPrint(
          '[DODO][CategoryService] fetchCategories → MOCK (Supabase not configured)');
      return _devCategories;
    }
    debugPrint(
        '[DODO][CategoryService] fetchCategories → SUPABASE (table: categories)');

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

  Future<List<SubcategoryModel>> fetchSubcategoriesByCategoryId(
    String categoryId,
  ) async {
    if (!_ready) {
      debugPrint(
          '[DODO][CategoryService] fetchSubcategoriesByCategoryId($categoryId) → MOCK');
      return _devSubcategories
          .where((s) => s.categoryId == categoryId)
          .toList();
    }
    debugPrint(
        '[DODO][CategoryService] fetchSubcategoriesByCategoryId($categoryId) → SUPABASE');

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

  // ── Services by subcategory ────────────────────────────────────────────────

  Future<List<ServiceModel>> fetchServicesBySubcategoryId(
    String subcategoryId,
  ) async {
    if (!_ready) {
      debugPrint(
          '[DODO][CategoryService] fetchServicesBySubcategoryId($subcategoryId) → MOCK');
      return _devServices
          .where((s) => s.subcategoryId == subcategoryId)
          .toList();
    }
    debugPrint(
        '[DODO][CategoryService] fetchServicesBySubcategoryId($subcategoryId) → SUPABASE (filter: sub_category_id)');

    final data = await _db
        .from('services')
        .select('*, sub_categories(id, name), categories(id, name)')
        .eq('sub_category_id', subcategoryId)
        .eq('is_active', true)
        .order('name', ascending: true);

    final results = (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .toList();
    debugPrint(
        '[DODO][CategoryService] fetchServicesBySubcategoryId($subcategoryId) → ${results.length} service(s) returned');
    return results;
  }

  // ── Service attributes ─────────────────────────────────────────────────────

  Future<List<ServiceAttributeModel>> fetchServiceAttributes(
    String serviceId,
  ) async {
    if (!_ready) {
      debugPrint(
          '[DODO][CategoryService] fetchServiceAttributes($serviceId) → MOCK');
      return _devAttributes
          .where((a) => a.serviceId == serviceId)
          .toList();
    }
    debugPrint(
        '[DODO][CategoryService] fetchServiceAttributes($serviceId) → SUPABASE');

    const optionsSelect =
        'service_attribute_options(id, attribute_id, option_name, price_adjustment)';

    final data = await _db
        .from('service_attributes')
        .select('*, $optionsSelect')
        .eq('service_id', serviceId)
        .order('name', ascending: true);

    final results = (data as List)
        .map((e) => ServiceAttributeModel.fromJson(e as Map<String, dynamic>))
        .toList();
    debugPrint(
        '[DODO][CategoryService] fetchServiceAttributes($serviceId) → ${results.length} attribute(s), '
        'option counts: ${results.map((a) => "${a.name}:${a.options.length}").join(", ")}');
    return results;
  }
}

// ── Dev dataset ───────────────────────────────────────────────────────────────
// IDs must stay aligned with HomeService._devCategories ('1'–'8').

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

// One primary service per subcategory.
// Type/variant distinctions (Front Load vs Top Load, etc.) become attributes.
final _devServices = [
  // ── Appliances ────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_ac',  name: 'AC Repair',        subcategoryId: 's28', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'AC Repair',       startingPrice: 499,  description: 'All brands — split, window and cassette'),
  const ServiceModel(id: 'svc_wm',  name: 'Washing Machine',  subcategoryId: 's29', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'Washing Machine',  startingPrice: 799,  description: 'Front load, top load and semi-automatic'),
  const ServiceModel(id: 'svc_rf',  name: 'Refrigerator',     subcategoryId: 's30', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'Refrigerator',     startingPrice: 599,  description: 'Single door, double door and side-by-side'),
  const ServiceModel(id: 'svc_mw',  name: 'Microwave Repair', subcategoryId: 's31', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'Microwave Repair', startingPrice: 399,  description: 'Solo, grill and convection microwaves'),
  const ServiceModel(id: 'svc_tv',  name: 'TV Repair',        subcategoryId: 's32', categoryId: '7', categoryName: 'Appliances', subcategoryName: 'TV Repair',        startingPrice: 699,  description: 'LCD, LED and OLED all screen types'),
  // ── Cleaning ──────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_hdc', name: 'Home Deep Clean',  subcategoryId: 's1',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Home Deep Clean',  startingPrice: 1299, description: 'Complete home sanitization top to bottom'),
  const ServiceModel(id: 'svc_kc',  name: 'Kitchen Cleaning', subcategoryId: 's2',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Kitchen Cleaning', startingPrice: 699,  description: 'Deep clean including chimney and cabinets'),
  const ServiceModel(id: 'svc_bc',  name: 'Bathroom Cleaning',subcategoryId: 's3',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Bathroom Cleaning',startingPrice: 499,  description: 'Tiles, fixtures and full sanitization'),
  const ServiceModel(id: 'svc_sc',  name: 'Sofa & Carpet',    subcategoryId: 's4',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Sofa & Carpet',    startingPrice: 599,  description: 'Steam cleaning for upholstery and carpet'),
  const ServiceModel(id: 'svc_oc',  name: 'Office Cleaning',  subcategoryId: 's5',  categoryId: '1', categoryName: 'Cleaning',   subcategoryName: 'Office Cleaning',  startingPrice: 999,  description: 'Commercial workspace deep cleaning'),
  // ── Plumbing ──────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_tf',  name: 'Tap & Faucet',     subcategoryId: 's6',  categoryId: '2', categoryName: 'Plumbing',   subcategoryName: 'Tap & Faucet',     startingPrice: 249,  description: 'Repair or replace taps and faucets'),
  const ServiceModel(id: 'svc_pr',  name: 'Pipe Repair',      subcategoryId: 's7',  categoryId: '2', categoryName: 'Plumbing',   subcategoryName: 'Pipe Repair',      startingPrice: 349,  description: 'Leak detection, fix and pipe work'),
  const ServiceModel(id: 'svc_dr',  name: 'Drain Cleaning',   subcategoryId: 's8',  categoryId: '2', categoryName: 'Plumbing',   subcategoryName: 'Drain Cleaning',   startingPrice: 299,  description: 'Clear blockages from any drain'),
  const ServiceModel(id: 'svc_wh',  name: 'Water Heater',     subcategoryId: 's9',  categoryId: '2', categoryName: 'Plumbing',   subcategoryName: 'Water Heater',     startingPrice: 399,  description: 'Geyser installation and repair'),
  const ServiceModel(id: 'svc_tr',  name: 'Toilet Repair',    subcategoryId: 's10', categoryId: '2', categoryName: 'Plumbing',   subcategoryName: 'Toilet Repair',    startingPrice: 199,  description: 'Flush, seat and cistern repair'),
  // ── Electrical ────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_fan', name: 'Fan Installation',  subcategoryId: 's11', categoryId: '3', categoryName: 'Electrical', subcategoryName: 'Fan Installation',  startingPrice: 299,  description: 'Ceiling, exhaust and wall fans'),
  const ServiceModel(id: 'svc_lf',  name: 'Light Fitting',    subcategoryId: 's12', categoryId: '3', categoryName: 'Electrical', subcategoryName: 'Light Fitting',    startingPrice: 199,  description: 'Bulbs, fixtures and strip lights'),
  const ServiceModel(id: 'svc_wm2', name: 'Wiring & MCB',     subcategoryId: 's13', categoryId: '3', categoryName: 'Electrical', subcategoryName: 'Wiring & MCB',     startingPrice: 499,  description: 'Wiring, circuit breakers and panels'),
  // ── Painting ──────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_wp',  name: 'Wall Painting',    subcategoryId: 's16', categoryId: '4', categoryName: 'Painting',   subcategoryName: 'Wall Painting',    startingPrice: 1499, description: 'Interior emulsion and texture painting'),
  const ServiceModel(id: 'svc_ep',  name: 'Exterior Paint',   subcategoryId: 's17', categoryId: '4', categoryName: 'Painting',   subcategoryName: 'Exterior Paint',   startingPrice: 2999, description: 'Weather-proof exterior coatings'),
  // ── Carpentry ─────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_fr',  name: 'Furniture Repair', subcategoryId: 's20', categoryId: '5', categoryName: 'Carpentry',  subcategoryName: 'Furniture Repair', startingPrice: 399,  description: 'Fix and restore all furniture types'),
  const ServiceModel(id: 'svc_dw',  name: 'Door & Window',    subcategoryId: 's21', categoryId: '5', categoryName: 'Carpentry',  subcategoryName: 'Door & Window',    startingPrice: 299,  description: 'Frame, hinge and lock repair'),
  // ── Pest Control ──────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_cc',  name: 'Cockroach Control',subcategoryId: 's24', categoryId: '6', categoryName: 'Pest Control',subcategoryName: 'Cockroach Control',startingPrice: 499,  description: 'Safe gel bait treatment'),
  const ServiceModel(id: 'svc_tc',  name: 'Termite Control',  subcategoryId: 's25', categoryId: '6', categoryName: 'Pest Control',subcategoryName: 'Termite Control',  startingPrice: 799,  description: 'Anti-termite drill and treat'),
  // ── Shifting ──────────────────────────────────────────────────────────────
  const ServiceModel(id: 'svc_hs',  name: 'Home Shifting',    subcategoryId: 's33', categoryId: '8', categoryName: 'Shifting',   subcategoryName: 'Home Shifting',    startingPrice: 2999, description: 'Full packing, loading and relocation'),
  const ServiceModel(id: 'svc_os',  name: 'Office Shifting',  subcategoryId: 's34', categoryId: '8', categoryName: 'Shifting',   subcategoryName: 'Office Shifting',  startingPrice: 4999, description: 'Corporate relocation specialists'),
];

// Attributes for each primary service.
// Type/variant selection is the first attribute where applicable.
final _devAttributes = [
  // ── AC Repair (svc_ac) ────────────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_ac_type', serviceId: 'svc_ac', name: 'AC Type',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_ac_split',   attributeId: 'attr_ac_type', optionName: 'Split AC'),
      const ServiceAttributeOptionModel(id: 'o_ac_window',  attributeId: 'attr_ac_type', optionName: 'Window AC'),
      const ServiceAttributeOptionModel(id: 'o_ac_cassette',attributeId: 'attr_ac_type', optionName: 'Cassette AC', priceAdjustment: 200),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_ac_ton', serviceId: 'svc_ac', name: 'Capacity',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_ac_1t',   attributeId: 'attr_ac_ton', optionName: '1 Ton'),
      const ServiceAttributeOptionModel(id: 'o_ac_15t',  attributeId: 'attr_ac_ton', optionName: '1.5 Ton'),
      const ServiceAttributeOptionModel(id: 'o_ac_2t',   attributeId: 'attr_ac_ton', optionName: '2 Ton', priceAdjustment: 100),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_ac_brand', serviceId: 'svc_ac', name: 'Brand',
    fieldType: 'radio', isRequired: false,
    options: [
      const ServiceAttributeOptionModel(id: 'o_ac_lg',     attributeId: 'attr_ac_brand', optionName: 'LG'),
      const ServiceAttributeOptionModel(id: 'o_ac_sam',    attributeId: 'attr_ac_brand', optionName: 'Samsung'),
      const ServiceAttributeOptionModel(id: 'o_ac_dai',    attributeId: 'attr_ac_brand', optionName: 'Daikin'),
      const ServiceAttributeOptionModel(id: 'o_ac_vol',    attributeId: 'attr_ac_brand', optionName: 'Voltas'),
      const ServiceAttributeOptionModel(id: 'o_ac_other',  attributeId: 'attr_ac_brand', optionName: 'Other'),
    ],
  ),
  // ── Washing Machine (svc_wm) ──────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_wm_type', serviceId: 'svc_wm', name: 'Machine Type',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_wm_fl',   attributeId: 'attr_wm_type', optionName: 'Front Load'),
      const ServiceAttributeOptionModel(id: 'o_wm_tl',   attributeId: 'attr_wm_type', optionName: 'Top Load'),
      const ServiceAttributeOptionModel(id: 'o_wm_semi', attributeId: 'attr_wm_type', optionName: 'Semi-Automatic'),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_wm_cap', serviceId: 'svc_wm', name: 'Capacity',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_wm_6kg', attributeId: 'attr_wm_cap', optionName: '6 KG'),
      const ServiceAttributeOptionModel(id: 'o_wm_7kg', attributeId: 'attr_wm_cap', optionName: '7 KG'),
      const ServiceAttributeOptionModel(id: 'o_wm_8kg', attributeId: 'attr_wm_cap', optionName: '8 KG', priceAdjustment: 100),
      const ServiceAttributeOptionModel(id: 'o_wm_9kg', attributeId: 'attr_wm_cap', optionName: '9 KG+', priceAdjustment: 200),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_wm_brand', serviceId: 'svc_wm', name: 'Brand',
    fieldType: 'radio', isRequired: false,
    options: [
      const ServiceAttributeOptionModel(id: 'o_wm_lg',    attributeId: 'attr_wm_brand', optionName: 'LG'),
      const ServiceAttributeOptionModel(id: 'o_wm_sam',   attributeId: 'attr_wm_brand', optionName: 'Samsung'),
      const ServiceAttributeOptionModel(id: 'o_wm_ifb',   attributeId: 'attr_wm_brand', optionName: 'IFB'),
      const ServiceAttributeOptionModel(id: 'o_wm_bsh',   attributeId: 'attr_wm_brand', optionName: 'Bosch'),
      const ServiceAttributeOptionModel(id: 'o_wm_other', attributeId: 'attr_wm_brand', optionName: 'Other'),
    ],
  ),
  // ── Refrigerator (svc_rf) ─────────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_rf_type', serviceId: 'svc_rf', name: 'Fridge Type',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_rf_single', attributeId: 'attr_rf_type', optionName: 'Single Door'),
      const ServiceAttributeOptionModel(id: 'o_rf_double', attributeId: 'attr_rf_type', optionName: 'Double Door', priceAdjustment: 200),
      const ServiceAttributeOptionModel(id: 'o_rf_sbs',    attributeId: 'attr_rf_type', optionName: 'Side by Side', priceAdjustment: 400),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_rf_brand', serviceId: 'svc_rf', name: 'Brand',
    fieldType: 'radio', isRequired: false,
    options: [
      const ServiceAttributeOptionModel(id: 'o_rf_lg',    attributeId: 'attr_rf_brand', optionName: 'LG'),
      const ServiceAttributeOptionModel(id: 'o_rf_sam',   attributeId: 'attr_rf_brand', optionName: 'Samsung'),
      const ServiceAttributeOptionModel(id: 'o_rf_wh',    attributeId: 'attr_rf_brand', optionName: 'Whirlpool'),
      const ServiceAttributeOptionModel(id: 'o_rf_other', attributeId: 'attr_rf_brand', optionName: 'Other'),
    ],
  ),
  // ── Microwave Repair (svc_mw) ─────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_mw_type', serviceId: 'svc_mw', name: 'Microwave Type',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_mw_solo',  attributeId: 'attr_mw_type', optionName: 'Solo'),
      const ServiceAttributeOptionModel(id: 'o_mw_grill', attributeId: 'attr_mw_type', optionName: 'Grill'),
      const ServiceAttributeOptionModel(id: 'o_mw_conv',  attributeId: 'attr_mw_type', optionName: 'Convection', priceAdjustment: 150),
    ],
  ),
  // ── Home Deep Clean (svc_hdc) ─────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_hdc_size', serviceId: 'svc_hdc', name: 'Property Size',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_hdc_1bhk', attributeId: 'attr_hdc_size', optionName: '1 BHK'),
      const ServiceAttributeOptionModel(id: 'o_hdc_2bhk', attributeId: 'attr_hdc_size', optionName: '2 BHK', priceAdjustment: 500),
      const ServiceAttributeOptionModel(id: 'o_hdc_3bhk', attributeId: 'attr_hdc_size', optionName: '3 BHK', priceAdjustment: 1200),
      const ServiceAttributeOptionModel(id: 'o_hdc_4bhk', attributeId: 'attr_hdc_size', optionName: '4 BHK+', priceAdjustment: 2000),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_hdc_freq', serviceId: 'svc_hdc', name: 'Frequency',
    fieldType: 'radio', isRequired: false,
    options: [
      const ServiceAttributeOptionModel(id: 'o_hdc_once', attributeId: 'attr_hdc_freq', optionName: 'One-time'),
      const ServiceAttributeOptionModel(id: 'o_hdc_mon',  attributeId: 'attr_hdc_freq', optionName: 'Monthly', priceAdjustment: -200),
    ],
  ),
  // ── Wall Painting (svc_wp) ────────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_wp_scope', serviceId: 'svc_wp', name: 'Scope',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_wp_1r',  attributeId: 'attr_wp_scope', optionName: '1 Room'),
      const ServiceAttributeOptionModel(id: 'o_wp_2r',  attributeId: 'attr_wp_scope', optionName: '2–3 Rooms', priceAdjustment: 1500),
      const ServiceAttributeOptionModel(id: 'o_wp_full',attributeId: 'attr_wp_scope', optionName: 'Full Home', priceAdjustment: 3500),
    ],
  ),
  ServiceAttributeModel(
    id: 'attr_wp_finish', serviceId: 'svc_wp', name: 'Finish',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_wp_matt',    attributeId: 'attr_wp_finish', optionName: 'Matt'),
      const ServiceAttributeOptionModel(id: 'o_wp_silk',    attributeId: 'attr_wp_finish', optionName: 'Silk', priceAdjustment: 300),
      const ServiceAttributeOptionModel(id: 'o_wp_texture', attributeId: 'attr_wp_finish', optionName: 'Texture', priceAdjustment: 700),
    ],
  ),
  // ── Tap & Faucet (svc_tf) ─────────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_tf_type', serviceId: 'svc_tf', name: 'Service Type',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_tf_repair',  attributeId: 'attr_tf_type', optionName: 'Repair Tap'),
      const ServiceAttributeOptionModel(id: 'o_tf_replace', attributeId: 'attr_tf_type', optionName: 'Replace Tap', priceAdjustment: 200),
    ],
  ),
  // ── Home Shifting (svc_hs) ────────────────────────────────────────────────
  ServiceAttributeModel(
    id: 'attr_hs_size', serviceId: 'svc_hs', name: 'Home Size',
    fieldType: 'radio', isRequired: true,
    options: [
      const ServiceAttributeOptionModel(id: 'o_hs_1bhk', attributeId: 'attr_hs_size', optionName: '1 BHK'),
      const ServiceAttributeOptionModel(id: 'o_hs_2bhk', attributeId: 'attr_hs_size', optionName: '2 BHK', priceAdjustment: 1000),
      const ServiceAttributeOptionModel(id: 'o_hs_3bhk', attributeId: 'attr_hs_size', optionName: '3 BHK+', priceAdjustment: 2500),
    ],
  ),
];
