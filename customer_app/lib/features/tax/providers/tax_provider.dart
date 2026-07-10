import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tax_settings_model.dart';
import '../services/tax_service.dart';

final taxSettingsProvider = FutureProvider<TaxSettingsModel>(
  (ref) => TaxService().getSettings(),
);
