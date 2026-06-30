import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/service_model.dart';
import '../../../models/faq_model.dart';
import '../../../models/addon_model.dart';

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
      debugPrint('[DODO][ServiceService] fetchServicesBySubcategoryId($subcategoryId) → MOCK (Supabase not configured)');
      final explicit =
          _devServices.where((s) => s.subcategoryId == subcategoryId).toList();
      return explicit.isNotEmpty ? explicit : _genericServices(subcategoryId);
    }
    debugPrint('[DODO][ServiceService] fetchServicesBySubcategoryId($subcategoryId) → SUPABASE (table: services + join subcategories/categories)');

    final data = await _db
        .from('services')
        .select('''
          *,
          sub_categories(name, categories(name)),
          service_faqs(id, question, answer, sort_order),
          service_add_ons(id, name, description, price, is_active)
        ''')
        .eq('sub_category_id', subcategoryId)
        .eq('is_active', true)
        .order('name', ascending: true);

    return (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Services by category (all subcategories) ─────────────────────────────

  Future<List<ServiceModel>> fetchServicesByCategoryId(
    String categoryId,
  ) async {
    if (!_ready) {
      debugPrint('[DODO][ServiceService] fetchServicesByCategoryId($categoryId) → MOCK');
      return _devServices;
    }
    debugPrint('[DODO][ServiceService] fetchServicesByCategoryId($categoryId) → SUPABASE');

    final data = await _db
        .from('services')
        .select('''
          *,
          sub_categories!inner(name, categories(name)),
          service_faqs(id, question, answer, sort_order),
          service_add_ons(id, name, description, price, is_active)
        ''')
        .filter('sub_categories.category_id', 'eq', categoryId)
        .eq('is_active', true)
        .order('name', ascending: true);

    return (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Single service by ID ───────────────────────────────────────────────────

  Future<ServiceModel?> fetchServiceById(String serviceId) async {
    if (!_ready) {
      debugPrint('[DODO][ServiceService] fetchServiceById($serviceId) → MOCK (Supabase not configured)');
      try {
        return _devServices.firstWhere((s) => s.id == serviceId);
      } catch (_) {
        return null;
      }
    }
    debugPrint('[DODO][ServiceService] fetchServiceById($serviceId) → SUPABASE (table: services + join subcategories/categories)');

    final data = await _db
        .from('services')
        .select('''
          *,
          sub_categories(name, categories(name)),
          service_faqs(id, question, answer, sort_order),
          service_add_ons(id, name, description, price, is_active)
        ''')
        .eq('id', serviceId)
        .maybeSingle();

    if (data == null) return null;
    return ServiceModel.fromJson(data);
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

// ── Common FAQ & add-on templates ─────────────────────────────────────────────

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
  AddOnModel(
      id: 'ca1',
      name: 'Express Service',
      description: 'Priority 2-hour slot',
      price: 199),
  AddOnModel(
      id: 'ca2',
      name: 'Post-Service Report',
      description: 'Detailed job-completion report',
      price: 99),
];

// ── Dev fallback dataset (shown only when Supabase is not configured) ─────────

final _devServices = [
  // Cleaning — s1: Home Deep Clean
  const ServiceModel(
    id: 's1_1', name: 'Basic Home Cleaning',
    description: 'Covers living room, bedrooms, kitchen countertops, and one bathroom.',
    startingPrice: 999, durationMinutes: 120,
    subcategoryId: 's1', categoryName: 'Cleaning', subcategoryName: 'Home Deep Clean',
    isFeatured: true,
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's1_2', name: 'Standard Home Deep Clean',
    description: 'Full home deep clean — all rooms, kitchen appliances, two bathrooms, balcony, and windows.',
    startingPrice: 1499, durationMinutes: 180,
    subcategoryId: 's1', categoryName: 'Cleaning', subcategoryName: 'Home Deep Clean',
    isFeatured: true,
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's1_3', name: 'Premium Deep Sanitization',
    description: 'Hospital-grade sanitization using HEPA equipment, UV treatment, and antimicrobial spray.',
    startingPrice: 2499, durationMinutes: 240,
    subcategoryId: 's1', categoryName: 'Cleaning', subcategoryName: 'Home Deep Clean',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Plumbing — s6: Tap & Faucet
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
    id: 's6_3', name: 'Full Bathroom Tap Upgrade',
    description: 'Replace all taps and mixer in one bathroom. Includes quality-checked fittings and a 1-year warranty.',
    startingPrice: 899, durationMinutes: 90,
    subcategoryId: 's6', categoryName: 'Plumbing', subcategoryName: 'Tap & Faucet',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Electrical — s11: Fan Installation
  const ServiceModel(
    id: 's11_1', name: 'Ceiling Fan Installation',
    description: 'Install a new ceiling fan on an existing hook point. Includes balancing and speed testing.',
    startingPrice: 349, durationMinutes: 45,
    subcategoryId: 's11', categoryName: 'Electrical', subcategoryName: 'Fan Installation',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's11_2', name: 'Exhaust Fan Installation',
    description: 'Fit an exhaust fan in bathroom or kitchen. Includes wiring, switch, and functional test.',
    startingPrice: 249, durationMinutes: 30,
    subcategoryId: 's11', categoryName: 'Electrical', subcategoryName: 'Fan Installation',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Painting — s16: Wall Painting
  const ServiceModel(
    id: 's16_1', name: 'Single Room Painting',
    description: '2 coats of premium emulsion paint for one room. Includes wall prep and putty.',
    startingPrice: 1499, durationMinutes: 240,
    subcategoryId: 's16', categoryName: 'Painting', subcategoryName: 'Wall Painting',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's16_2', name: '2BHK Interior Painting',
    description: 'Complete interior for a standard 2BHK — all rooms, kitchen, and 2 bathrooms.',
    startingPrice: 4999, durationMinutes: 480,
    subcategoryId: 's16', categoryName: 'Painting', subcategoryName: 'Wall Painting',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Carpentry — s20: Furniture Repair
  const ServiceModel(
    id: 's20_1', name: 'Chair & Stool Repair',
    description: 'Fix wobbling legs, broken joints, or damaged upholstery. On-site repair in most cases.',
    startingPrice: 349, durationMinutes: 60,
    subcategoryId: 's20', categoryName: 'Carpentry', subcategoryName: 'Furniture Repair',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's20_2', name: 'Wardrobe Repair',
    description: 'Realign doors, replace hinges, fix broken shelves or drawer slides.',
    startingPrice: 599, durationMinutes: 90,
    subcategoryId: 's20', categoryName: 'Carpentry', subcategoryName: 'Furniture Repair',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Pest Control — s24: Cockroach Control
  const ServiceModel(
    id: 's24_1', name: 'Kitchen Cockroach Treatment',
    description: 'Targeted gel-bait treatment for kitchen cabinets, appliances, and drains. Odourless and safe.',
    startingPrice: 499, durationMinutes: 60,
    subcategoryId: 's24', categoryName: 'Pest Control', subcategoryName: 'Cockroach Control',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's24_2', name: 'Full Home Cockroach Treatment',
    description: 'Gel bait + spray treatment for the entire home. Effective for 3 months, child and pet safe.',
    startingPrice: 799, durationMinutes: 90,
    subcategoryId: 's24', categoryName: 'Pest Control', subcategoryName: 'Cockroach Control',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Appliances — s28: AC Service
  const ServiceModel(
    id: 's28_1', name: 'AC Regular Service',
    description: 'Filter clean, coil wash, drain pipe check, and performance test for 1 split AC unit.',
    startingPrice: 499, durationMinutes: 60,
    subcategoryId: 's28', categoryName: 'Appliances', subcategoryName: 'AC Service',
    isFeatured: true,
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's28_2', name: 'AC Deep Clean',
    description: 'Full jet-wash of indoor and outdoor units, evaporator coil cleaning, and drain sanitization.',
    startingPrice: 799, durationMinutes: 120,
    subcategoryId: 's28', categoryName: 'Appliances', subcategoryName: 'AC Service',
    isFeatured: true,
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's28_3', name: 'AC Gas Refill + Service',
    description: 'Full service plus refrigerant top-up. Restores cooling performance to factory levels.',
    startingPrice: 1299, durationMinutes: 90,
    subcategoryId: 's28', categoryName: 'Appliances', subcategoryName: 'AC Service',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),

  // Shifting — s33: Home Shifting
  const ServiceModel(
    id: 's33_1', name: '1BHK Home Shifting',
    description: 'Full packing, loading, transport, and unloading for a 1BHK flat. Transit insurance included.',
    startingPrice: 2999, durationMinutes: 180,
    subcategoryId: 's33', categoryName: 'Shifting', subcategoryName: 'Home Shifting',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
  const ServiceModel(
    id: 's33_2', name: '2BHK Home Shifting',
    description: 'Comprehensive relocation for a 2BHK. Includes furniture dismantling, packing, and reassembly.',
    startingPrice: 4999, durationMinutes: 300,
    subcategoryId: 's33', categoryName: 'Shifting', subcategoryName: 'Home Shifting',
    faqs: _commonFaqs, addOns: _commonAddOns,
  ),
];
