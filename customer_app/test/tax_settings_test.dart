import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/tax/models/tax_settings_model.dart';

TaxSettingsModel _model({
  bool isEnabled = true,
  String taxType = 'percentage',
  double taxValue = 18.0,
  bool applyOnServices = true,
}) =>
    TaxSettingsModel(
      isEnabled: isEnabled,
      taxName: 'GST',
      taxType: taxType,
      taxValue: taxValue,
      applyOnServices: applyOnServices,
      applyOnAddons: true,
      applyOnPackages: false,
      displaySeparately: true,
    );

void main() {
  group('TaxSettingsModel.computeTax', () {
    test('18% on 1000 = 180', () {
      expect(_model().computeTax(1000.0), 180.0);
    });

    test('5% on 200 = 10', () {
      expect(_model(taxValue: 5.0).computeTax(200.0), 10.0);
    });

    test('zero subtotal yields zero tax', () {
      expect(_model().computeTax(0.0), 0.0);
    });

    test('disabled tax always returns 0', () {
      expect(_model(isEnabled: false).computeTax(1000.0), 0.0);
    });

    test('applyOnServices=false returns 0 even when tax is enabled', () {
      expect(_model(applyOnServices: false).computeTax(1000.0), 0.0);
    });

    test('fixed tax ignores subtotal', () {
      final fixed = _model(taxType: 'fixed', taxValue: 50.0);
      expect(fixed.computeTax(1000.0), 50.0);
      expect(fixed.computeTax(100.0), 50.0);
      expect(fixed.computeTax(0.0), 50.0);
    });

    test('fractional percentage', () {
      // 7.5% of 400 = 30
      expect(_model(taxValue: 7.5).computeTax(400.0), 30.0);
    });

    test('disabled + fixed still returns 0', () {
      final m = _model(isEnabled: false, taxType: 'fixed', taxValue: 99.0);
      expect(m.computeTax(500.0), 0.0);
    });
  });

  group('TaxSettingsModel.displayLabel', () {
    test('integer percentage shows without decimal', () {
      expect(_model(taxType: 'percentage', taxValue: 18.0).displayLabel, 'GST (18%)');
    });

    test('fractional percentage shows one decimal', () {
      expect(_model(taxType: 'percentage', taxValue: 7.5).displayLabel, 'GST (7.5%)');
    });

    test('fixed tax shows rupee amount', () {
      final m = TaxSettingsModel(
        isEnabled: true,
        taxName: 'SGST',
        taxType: 'fixed',
        taxValue: 50.0,
        applyOnServices: true,
        applyOnAddons: true,
        applyOnPackages: false,
        displaySeparately: true,
      );
      expect(m.displayLabel, 'SGST (₹50)');
    });
  });

  group('TaxSettingsModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = TaxSettingsModel.fromJson({
        'id': 'abc',
        'is_enabled': true,
        'tax_name': 'VAT',
        'tax_type': 'fixed',
        'tax_value': 25.0,
        'apply_on_services': false,
        'apply_on_addons': false,
        'apply_on_packages': true,
        'display_separately': false,
      });
      expect(m.id, 'abc');
      expect(m.isEnabled, true);
      expect(m.taxName, 'VAT');
      expect(m.taxType, 'fixed');
      expect(m.taxValue, 25.0);
      expect(m.applyOnServices, false);
      expect(m.applyOnAddons, false);
      expect(m.applyOnPackages, true);
      expect(m.displaySeparately, false);
    });

    test('uses defaults for missing fields', () {
      final m = TaxSettingsModel.fromJson({});
      expect(m.isEnabled, true);
      expect(m.taxName, 'GST');
      expect(m.taxType, 'percentage');
      expect(m.taxValue, 18.0);
      expect(m.applyOnServices, true);
      expect(m.applyOnAddons, true);
      expect(m.applyOnPackages, false);
      expect(m.displaySeparately, true);
    });
  });

  group('TaxSettingsModel.defaults', () {
    test('default constant matches expected values', () {
      const d = TaxSettingsModel.defaults;
      expect(d.isEnabled, true);
      expect(d.taxName, 'GST');
      expect(d.taxType, 'percentage');
      expect(d.taxValue, 18.0);
      expect(d.applyOnServices, true);
    });
  });
}
