import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tax_settings_model.dart';

class TaxService {
  final _client = Supabase.instance.client;

  Future<TaxSettingsModel> getSettings() async {
    try {
      final row = await _client
          .from('tax_settings')
          .select()
          .limit(1)
          .maybeSingle();
      if (row == null) return TaxSettingsModel.defaults;
      return TaxSettingsModel.fromJson(row);
    } catch (_) {
      return TaxSettingsModel.defaults;
    }
  }
}
