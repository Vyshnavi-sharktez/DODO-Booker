import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/settings/domain/models/settings_defaults.dart';
import 'package:admin_panel/features/settings/application/providers/settings_providers.dart';

void main() {
  group('Global refund period — kSettingDefaults', () {
    test('default_refund_period_days is present with value "30"', () {
      expect(kSettingDefaults.containsKey('default_refund_period_days'), isTrue);
      expect(kSettingDefaults['default_refund_period_days'], '30');
    });

    test('default_warranty_days is still present (regression)', () {
      expect(kSettingDefaults.containsKey('default_warranty_days'), isTrue);
    });

    test('parseable as integer >= 0', () {
      final raw = kSettingDefaults['default_refund_period_days']!;
      final days = int.tryParse(raw);
      expect(days, isNotNull);
      expect(days!, greaterThanOrEqualTo(0));
    });
  });

  group('SettingsNotifier.effectiveValue — refund period fallback', () {
    test('returns stored value when present', () {
      const settings = {'default_refund_period_days': '7'};
      expect(
        SettingsNotifier.effectiveValue(settings, 'default_refund_period_days'),
        '7',
      );
    });

    test('falls back to kSettingDefaults value when key absent from DB', () {
      const settings = <String, String>{};
      final result = SettingsNotifier.effectiveValue(
          settings, 'default_refund_period_days');
      expect(result, '30');
    });

    test('returns empty string for unknown key (no default)', () {
      const settings = <String, String>{};
      expect(
        SettingsNotifier.effectiveValue(settings, 'nonexistent_key'),
        '',
      );
    });

    test('overridden to 0 disables refunds (value "0" is valid)', () {
      const settings = {'default_refund_period_days': '0'};
      final result = SettingsNotifier.effectiveValue(
          settings, 'default_refund_period_days');
      expect(result, '0');
      expect(int.parse(result), 0);
    });

    test('overridden to 365 — maximum boundary', () {
      const settings = {'default_refund_period_days': '365'};
      final result = SettingsNotifier.effectiveValue(
          settings, 'default_refund_period_days');
      expect(int.parse(result), 365);
    });
  });
}
