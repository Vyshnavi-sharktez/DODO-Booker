import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/addon_model.dart';
import '../../../models/faq_model.dart';
import '../../../models/service_model.dart';

class ServiceService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Services by subcategory ────────────────────────────────────────────────

  Future<List<ServiceModel>> fetchServicesBySubcategoryId(
    String subcategoryId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][ServiceService] fetchServicesBySubcategoryId($subcategoryId) → MOCK');
      final explicit =
          _devServices.where((s) => s.subcategoryId == subcategoryId).toList();
      return explicit.isNotEmpty ? explicit : _genericServices(subcategoryId);
    }
    debugPrint('[DODO][ServiceService] fetchServicesBySubcategoryId($subcategoryId) → get_catalog_node_children');

    final childData = await _db.rpc(
      'get_catalog_node_children',
      params: {'p_parent_id': subcategoryId},
    );

    final nodes = (childData as List)
        .map((e) => e as Map<String, dynamic>)
        .where((r) =>
            (r['is_bookable'] as bool? ?? false) &&
            (r['is_active'] as bool? ?? true))
        .toList();

    if (nodes.isEmpty) return [];

    return _enrichAndBuild(nodes, subcategoryId: subcategoryId);
  }

  // ── Services by category (all descendant bookable nodes) ──────────────────

  Future<List<ServiceModel>> fetchServicesByCategoryId(
    String categoryId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][ServiceService] fetchServicesByCategoryId($categoryId) → MOCK');
      return _devServices;
    }
    debugPrint('[DODO][ServiceService] fetchServicesByCategoryId($categoryId) → catalog_nodes_view (2-hop)');

    // Step 1 — get subcategory IDs (direct children of category node)
    final subcatRpc = await _db.rpc(
      'get_catalog_node_children',
      params: {'p_parent_id': categoryId},
    );
    final subcatIds = (subcatRpc as List)
        .map((e) => e['id'] as String)
        .toList();

    if (subcatIds.isEmpty) return [];

    // Step 2 — get service relationship rows for those subcategories
    final relData = await _db
        .from('catalog_node_relationships')
        .select('parent_id, child_id')
        .inFilter('parent_id', subcatIds);

    final parentOfChild = <String, String>{
      for (final r in (relData as List))
        r['child_id'] as String: r['parent_id'] as String,
    };

    final serviceIds = parentOfChild.keys.toList();
    if (serviceIds.isEmpty) return [];

    // Step 3 — fetch catalog_node data for service IDs
    final nodeData = await _db
        .from('catalog_nodes_view')
        .select()
        .inFilter('id', serviceIds)
        .eq('is_bookable', true)
        .eq('is_active', true)
        .order('name', ascending: true);

    final nodes = (nodeData as List)
        .map((e) {
          final r = Map<String, dynamic>.from(e as Map<String, dynamic>);
          // Inject the sub_category_id from the relationship map
          r['sub_category_id_override'] = parentOfChild[r['id']];
          return r;
        })
        .toList();

    return _enrichAndBuild(nodes);
  }

  // ── Single service by ID ───────────────────────────────────────────────────

  Future<ServiceModel?> fetchServiceById(String serviceId) async {
    if (!_ready) {
      debugPrint('[DODO][ServiceService] fetchServiceById($serviceId) → MOCK');
      try {
        return _devServices.firstWhere((s) => s.id == serviceId);
      } catch (_) {
        return null;
      }
    }
    debugPrint('[DODO][ServiceService] fetchServiceById($serviceId) → catalog_nodes_view');

    final data = await _db
        .from('catalog_nodes_view')
        .select()
        .eq('id', serviceId)
        .eq('is_bookable', true)
        .maybeSingle();

    if (data == null) return null;

    final nodes = [Map<String, dynamic>.from(data)];
    final results = await _enrichAndBuild(nodes);
    return results.isEmpty ? null : results.first;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<List<ServiceModel>> _enrichAndBuild(
    List<Map<String, dynamic>> nodes, {
    String? subcategoryId,
  }) async {
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
      addonsByNode
          .putIfAbsent(sid, () => [])
          .add(addon as Map<String, dynamic>);
    }

    return nodes.map((r) {
      final nodeId = r['id'] as String;
      // parent_name = the direct parent of the service = subcategory name
      final parentName = r['parent_name'] as String?;
      final subCatId = subcategoryId ??
          r['sub_category_id_override'] as String? ??
          (r['parent_ids'] as List?)?.firstOrNull as String?;

      return ServiceModel.fromJson({
        ...r,
        'sub_category_id': subCatId,
        'subcategory_name': parentName,
        'category_name': null,
        'service_faqs': faqsByNode[nodeId] ?? [],
        'addons': addonsByNode[nodeId] ?? [],
      });
    }).toList();
  }
}

// ── Fallback generator for subcategories not in the dev list ──────────────────

List<ServiceModel> _genericServices(String subcategoryId) => [
      ServiceModel(
        id: '${subcategoryId}_1',
        name: 'Basic Package',
        description:
            'Our basic package covers essential service needs with trained professionals and quality equipment.',
        startingPrice: 499,
        durationMinutes: 60,
        subcategoryId: subcategoryId,
        faqs: _commonFaqs,
        addOns: _commonAddOns,
      ),
      ServiceModel(
        id: '${subcategoryId}_2',
        name: 'Standard Package',
        description:
            'Our most popular choice — comprehensive coverage with premium products and a satisfaction guarantee.',
        startingPrice: 899,
        durationMinutes: 90,
        subcategoryId: subcategoryId,
        faqs: _commonFaqs,
        addOns: _commonAddOns,
      ),
      ServiceModel(
        id: '${subcategoryId}_3',
        name: 'Premium Package',
        description:
            'Top-tier service with priority scheduling, senior professionals, and extended warranty.',
        startingPrice: 1499,
        durationMinutes: 120,
        subcategoryId: subcategoryId,
        faqs: _commonFaqs,
        addOns: _commonAddOns,
      ),
    ];

const _commonFaqs = [
  FaqModel(
    id: 'cf1',
    question: 'How many professionals will arrive?',
    answer:
        'Depending on the package, 1–2 trained professionals will arrive. Large jobs may require 2–3.',
  ),
  FaqModel(
    id: 'cf2',
    question: 'What if I am not satisfied?',
    answer:
        'We offer a 100% satisfaction guarantee. If you are unhappy, we will revisit at no extra cost.',
  ),
  FaqModel(
    id: 'cf3',
    question: 'Can I reschedule or cancel?',
    answer:
        'Yes. You can reschedule or cancel up to 4 hours before the appointment without any charges.',
  ),
];

const _commonAddOns = [
  AddOnModel(id: 'ca1', name: 'Express Service', description: 'Priority 2-hour slot', price: 199),
  AddOnModel(id: 'ca2', name: 'Post-Service Report', description: 'Detailed job-completion report', price: 99),
];

final _devServices = [
  // Cleaning — s1: Home Deep Clean
  const ServiceModel(
    id: 's1_1', name: 'Basic Home Cleaning',
    description: 'Covers living room, bedrooms, kitchen countertops, and one bathroom.',
    startingPrice: 999, durationMinutes: 120,
    subcategoryId: 's1', categoryName: 'Cleaning', subcategoryName: 'Home Deep Clean',
    isFeatured: true, faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's1_2', name: 'Standard Home Deep Clean',
    description: 'Full home deep clean — all rooms, kitchen appliances, two bathrooms, balcony, and windows.',
    startingPrice: 1499, durationMinutes: 180,
    subcategoryId: 's1', categoryName: 'Cleaning', subcategoryName: 'Home Deep Clean',
    isFeatured: true, faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's1_3', name: 'Premium Deep Sanitization',
    description: 'Hospital-grade sanitization using HEPA equipment, UV treatment, and antimicrobial spray.',
    startingPrice: 2499, durationMinutes: 240,
    subcategoryId: 's1', categoryName: 'Cleaning', subcategoryName: 'Home Deep Clean',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's6_1', name: 'Tap Leak Repair',
    description: 'Fix dripping taps, worn washers, and loose fittings across your home.',
    startingPrice: 299, durationMinutes: 45,
    subcategoryId: 's6', categoryName: 'Plumbing', subcategoryName: 'Tap & Faucet',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's6_2', name: 'Faucet Replacement',
    description: 'Replace old or damaged faucets. Labour and installation included.',
    startingPrice: 499, durationMinutes: 60,
    subcategoryId: 's6', categoryName: 'Plumbing', subcategoryName: 'Tap & Faucet',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's11_1', name: 'Ceiling Fan Installation',
    description: 'Install a new ceiling fan on an existing hook point. Includes balancing and speed testing.',
    startingPrice: 349, durationMinutes: 45,
    subcategoryId: 's11', categoryName: 'Electrical', subcategoryName: 'Fan Installation',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's28_1', name: 'AC Regular Service',
    description: 'Filter clean, coil wash, drain pipe check, and performance test for 1 split AC unit.',
    startingPrice: 499, durationMinutes: 60,
    subcategoryId: 's28', categoryName: 'Appliances', subcategoryName: 'AC Service',
    isFeatured: true, faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's28_2', name: 'AC Deep Clean',
    description: 'Full jet-wash of indoor and outdoor units, evaporator coil cleaning, and drain sanitization.',
    startingPrice: 799, durationMinutes: 120,
    subcategoryId: 's28', categoryName: 'Appliances', subcategoryName: 'AC Service',
    isFeatured: true, faqs: _commonFaqs, addOns: _commonAddOns,
  ),
];
