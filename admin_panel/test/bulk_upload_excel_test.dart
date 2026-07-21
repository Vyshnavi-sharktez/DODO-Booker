import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/features/bulk_upload/data/excel_utils.dart' as xu;

// Columns matching CatalogBulkModule.templateColumns
const _cols = [
  'level_1', 'level_2', 'level_3', 'level_4', 'level_5',
  'is_bookable', 'base_price', 'estimated_duration',
  'minimum_order_amount', 'description', 'icon_key', 'sort_order', 'is_active',
];

void main() {
  group('generateTemplate → parseXlsx round-trip', () {
    test('template bytes are non-empty and decode without error', () {
      final bytes = xu.generateTemplate(
        columns: _cols,
        exampleRows: [
          ['AC Services', '', '', '', '', 'FALSE', '', '', '', 'Air cond', '', '1', 'TRUE'],
          ['AC Services', 'AC Repair', '', '', '', 'TRUE', '299', '60', '199', '', 'ac_repair', '1', 'TRUE'],
          ['Home Cleaning', 'Deep Cleaning', 'Kitchen Deep Clean', '', '', 'TRUE', '499', '90', '299', '', '', '1', 'TRUE'],
        ],
        instructions: 'Test instructions\nLine 2',
      );

      print('Template bytes: ${bytes.length}');
      expect(bytes.length, greaterThan(0));

      // Decode and verify sheet names
      final workbook = Excel.decodeBytes(bytes.toList());
      final sheets = workbook.tables.keys.toList();
      print('Sheet names: $sheets');
      expect(sheets, contains('Template'));
      expect(sheets, isNot(contains('Sheet1')));
    });

    test('case 1 — simple row: level_1 only, is_bookable=FALSE, is_active=TRUE', () {
      final templateBytes = xu.generateTemplate(
        columns: _cols,
        exampleRows: const [],
        instructions: 'Instructions',
      );

      // Simulate a user-filled file by creating a new workbook with the same
      // structure that Excel would produce after saving.
      final userFile = Excel.createExcel();
      final sheet = userFile['Template'];

      // Write headers
      sheet.appendRow(_cols.map<CellValue>(TextCellValue.new).toList());

      // Write one simple row
      sheet.appendRow([
        TextCellValue('Test Category'), // level_1
        null, null, null, null,         // level_2..5 blank
        TextCellValue('FALSE'),         // is_bookable
        null, null, null, null, null,  // base_price..icon_key blank
        TextCellValue('1'),            // sort_order
        TextCellValue('TRUE'),         // is_active
      ]);

      userFile.delete('Sheet1');
      final encoded = Uint8List.fromList(userFile.encode()!);
      print('User-file bytes: ${encoded.length}');

      final rows = xu.parseXlsx(encoded);
      print('Parsed rows: $rows');

      expect(rows.length, 1);
      expect(rows[0]['level_1'], 'Test Category');
      expect(rows[0]['level_2'], isNull); // blank cell → null
      expect(rows[0]['is_bookable'], 'FALSE');
      expect(rows[0]['is_active'], 'TRUE');
    });

    test('case 2 — 3-level bookable row with blank level_4 and level_5', () {
      final userFile = Excel.createExcel();
      final sheet = userFile['Template'];

      sheet.appendRow(_cols.map<CellValue>(TextCellValue.new).toList());

      sheet.appendRow([
        TextCellValue('Home Cleaning'),    // level_1
        TextCellValue('Deep Cleaning'),    // level_2
        TextCellValue('Kitchen Deep Clean'), // level_3
        null,                              // level_4 blank
        null,                              // level_5 blank
        TextCellValue('TRUE'),             // is_bookable
        TextCellValue('499'),              // base_price
        TextCellValue('90'),               // estimated_duration
        TextCellValue('299'),              // minimum_order_amount
        null, null,                        // description, icon_key blank
        TextCellValue('1'),                // sort_order
        TextCellValue('TRUE'),             // is_active
      ]);

      userFile.delete('Sheet1');
      final encoded = Uint8List.fromList(userFile.encode()!);
      print('User-file bytes: ${encoded.length}');

      final rows = xu.parseXlsx(encoded);
      print('Parsed rows: $rows');

      expect(rows.length, 1);
      expect(rows[0]['level_1'], 'Home Cleaning');
      expect(rows[0]['level_2'], 'Deep Cleaning');
      expect(rows[0]['level_3'], 'Kitchen Deep Clean');
      expect(rows[0]['level_4'], isNull); // blank cell → null
      expect(rows[0]['level_5'], isNull); // blank cell → null
      expect(rows[0]['is_bookable'], 'TRUE');
      expect(rows[0]['base_price'], '499');
    });

    test('case 3 — round-trip of the actual generated catalog template', () {
      final templateBytes = xu.generateTemplate(
        columns: _cols,
        exampleRows: [
          ['AC Services', '', '', '', '', 'FALSE', '', '', '', 'Air conditioner services', '', '1', 'TRUE'],
          ['AC Services', 'AC Repair', '', '', '', 'TRUE', '299', '60', '199', 'AC repair and servicing', 'ac_repair', '1', 'TRUE'],
          ['Home Cleaning', 'Deep Cleaning', 'Kitchen Deep Clean', '', '', 'TRUE', '499', '90', '299', '', '', '1', 'TRUE'],
        ],
        instructions: 'CATALOG BULK UPLOAD — Instructions\n\nFill levels left-to-right.',
      );

      print('Template bytes: ${templateBytes.length}');

      final rows = xu.parseXlsx(templateBytes);
      print('Parsed rows (${rows.length}):');
      for (final r in rows) print('  $r');

      expect(rows.length, 3);
      expect(rows[0]['level_1'], 'AC Services');
      expect(rows[0]['level_2'], isNull); // blank cell → null
      expect(rows[0]['is_bookable'], 'FALSE');
      expect(rows[1]['level_1'], 'AC Services');
      expect(rows[1]['level_2'], 'AC Repair');
      expect(rows[1]['is_bookable'], 'TRUE');
      expect(rows[1]['base_price'], '299');
    });
  });
}
