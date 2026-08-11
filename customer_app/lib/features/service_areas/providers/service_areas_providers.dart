import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceAreaModel {
  final String id;
  final String name;
  final String city;
  final double radiusKm;

  const ServiceAreaModel({
    required this.id,
    required this.name,
    required this.city,
    required this.radiusKm,
  });

  factory ServiceAreaModel.fromJson(Map<String, dynamic> j) => ServiceAreaModel(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String,
        radiusKm: (j['radius_km'] as num).toDouble(),
      );
}

final serviceAreasProvider =
    FutureProvider.autoDispose<List<ServiceAreaModel>>((ref) async {
  final rows = await Supabase.instance.client
      .from('service_availability_areas')
      .select('id, name, city, radius_km')
      .eq('is_active', true)
      .order('city')
      .order('name');
  return (rows as List<dynamic>)
      .map((r) => ServiceAreaModel.fromJson(r as Map<String, dynamic>))
      .toList();
});
