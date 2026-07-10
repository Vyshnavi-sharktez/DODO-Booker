import 'package:supabase_flutter/supabase_flutter.dart';

class TaxSettingsConfig {
  final String? id;
  final bool isEnabled;
  final String taxName;
  final String taxType; // 'percentage' | 'fixed'
  final double taxValue;
  final bool applyOnServices;
  final bool applyOnAddons;
  final bool applyOnPackages;
  final bool displaySeparately;

  const TaxSettingsConfig({
    this.id,
    required this.isEnabled,
    required this.taxName,
    required this.taxType,
    required this.taxValue,
    required this.applyOnServices,
    required this.applyOnAddons,
    required this.applyOnPackages,
    required this.displaySeparately,
  });

  factory TaxSettingsConfig.defaults() => const TaxSettingsConfig(
        isEnabled: true,
        taxName: 'GST',
        taxType: 'percentage',
        taxValue: 18.0,
        applyOnServices: true,
        applyOnAddons: true,
        applyOnPackages: false,
        displaySeparately: true,
      );

  factory TaxSettingsConfig.fromMap(Map<String, dynamic> m) => TaxSettingsConfig(
        id: m['id'] as String?,
        isEnabled: (m['is_enabled'] as bool?) ?? true,
        taxName: (m['tax_name'] as String?) ?? 'GST',
        taxType: (m['tax_type'] as String?) ?? 'percentage',
        taxValue: (m['tax_value'] as num?)?.toDouble() ?? 18.0,
        applyOnServices: (m['apply_on_services'] as bool?) ?? true,
        applyOnAddons: (m['apply_on_addons'] as bool?) ?? true,
        applyOnPackages: (m['apply_on_packages'] as bool?) ?? false,
        displaySeparately: (m['display_separately'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'is_enabled': isEnabled,
        'tax_name': taxName,
        'tax_type': taxType,
        'tax_value': taxValue,
        'apply_on_services': applyOnServices,
        'apply_on_addons': applyOnAddons,
        'apply_on_packages': applyOnPackages,
        'display_separately': displaySeparately,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class TaxSettingsRepository {
  final SupabaseClient _client;
  const TaxSettingsRepository(this._client);

  Future<TaxSettingsConfig> fetch() async {
    final rows = await _client.from('tax_settings').select().limit(1);
    if (rows.isEmpty) return TaxSettingsConfig.defaults();
    return TaxSettingsConfig.fromMap(rows.first);
  }

  Future<TaxSettingsConfig> save(TaxSettingsConfig config) async {
    final payload = config.toMap();
    if (config.id != null) {
      await _client
          .from('tax_settings')
          .update(payload)
          .eq('id', config.id!);
      return config;
    } else {
      final row = await _client
          .from('tax_settings')
          .insert(payload)
          .select()
          .single();
      return TaxSettingsConfig.fromMap(row);
    }
  }
}
