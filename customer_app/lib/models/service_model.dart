import 'faq_model.dart';
import 'addon_model.dart';

class ServiceModel {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final double startingPrice;
  final int? durationMinutes;
  final String? categoryId;
  final String? categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final double rating;
  final int reviewCount;
  final bool isFeatured;
  final bool isActive;
  final List<FaqModel> faqs;
  final List<AddOnModel> addOns;

  const ServiceModel({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.startingPrice,
    this.durationMinutes,
    this.categoryId,
    this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.isFeatured = false,
    this.isActive = true,
    this.faqs = const [],
    this.addOns = const [],
  });

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    // Supabase join: services.select('*, sub_categories(name, categories(name))')
    final subData = json['sub_categories'] as Map<String, dynamic>?;
    final catData = subData?['categories'] as Map<String, dynamic>?;

    return ServiceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      // DB column: base_price. Legacy mock keys: price, starting_price.
      startingPrice: ((json['base_price'] ?? json['price'] ?? json['starting_price']) as num).toDouble(),
      // DB column: estimated_duration. Legacy mock keys: duration, duration_minutes.
      durationMinutes: (json['estimated_duration'] ?? json['duration'] ?? json['duration_minutes']) as int?,
      categoryId: json['category_id'] as String?,
      // Resolve from flat key first, then from Supabase join result
      categoryName:
          json['category_name'] as String? ?? catData?['name'] as String?,
      subcategoryId: json['subcategory_id'] as String?,
      subcategoryName: json['subcategory_name'] as String? ??
          subData?['name'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['review_count'] as int?) ?? 0,
      isFeatured: (json['is_featured'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
      faqs: (json['faqs'] as List<dynamic>?)
              ?.map((e) => FaqModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      addOns: (json['add_ons'] as List<dynamic>?)
              ?.map((e) => AddOnModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
