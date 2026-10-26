import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../bulk_upload_module.dart';
import '../../models/bulk_row.dart';
import '../excel_utils.dart' as xu;

class AddonBulkModule extends BulkUploadModule {
  @override
  String get moduleTitle => 'Add-ons';

  @override
  String get templateFilename => 'addons_template.xlsx';

  @override
  List<String> get templateColumns => [
        'addon_name',
        'price',
        'description',
        'is_active',
      ];

  @override
  List<List<String>> get exampleRows => [
        ['Extra Labour (1 hr)', '149', 'One hour of extra labour', 'TRUE'],
        ['Gas Refill', '299', 'Refrigerant gas refill', 'TRUE'],
      ];

  @override
  String get instructionsText => '''ADD-ONS BULK UPLOAD — Instructions

Required columns:
  addon_name : Name of the add-on
  price      : Price in ₹ (numeric)

Optional columns:
  description : Short description
  is_active   : TRUE or FALSE (default TRUE)

Duplicate handling:
  An add-on with the same name (case-insensitive) and identical fields is SKIPPED.
  If the name matches but any field differs, the existing record is UPDATED.
  Duplicate names within the uploaded file are SKIPPED after the first occurrence.

Notes:
  - Column headers in row 1 must not be changed.
  - Keep this file as .xlsx format.''';

  @override
  List<Map<String, String?>> parseXlsx(Uint8List bytes) => xu.parseXlsx(bytes);

  @override
  Future<List<BulkRow>> validateRows(List<Map<String, String?>> rawRows) async {
    final client = Supabase.instance.client;
    final existing = await _loadExistingAddons(client);

    final result = <BulkRow>[];
    final seenNames = <String>{};

    for (var i = 0; i < rawRows.length; i++) {
      final row = rawRows[i];
      final rowNum = i + 2;
      final errors = <String>[];

      final addonName = (row['addon_name'] ?? '').trim();
      final priceStr = (row['price'] ?? '').trim();

      if (addonName.isEmpty) errors.add('addon_name is required');
      if (priceStr.isEmpty) errors.add('price is required');
      if (priceStr.isNotEmpty && double.tryParse(priceStr) == null) {
        errors.add('price must be a number');
      }

      if (errors.isNotEmpty) {
        result.add(BulkRow(
          rowNumber: rowNum,
          raw: row,
          status: RowStatus.invalid,
          errors: errors,
          displayLabel: addonName,
        ));
        continue;
      }

      final nameLower = addonName.toLowerCase();

      // Within-upload duplicate.
      if (seenNames.contains(nameLower)) {
        result.add(BulkRow(
          rowNumber: rowNum,
          raw: row,
          status: RowStatus.skipped,
          skipReason: 'Duplicate name in this upload: "$addonName"',
          displayLabel: addonName,
        ));
        continue;
      }
      seenNames.add(nameLower);

      final existingAddon = existing[nameLower];
      if (existingAddon != null) {
        if (_addonFieldsChanged(row, existingAddon)) {
          result.add(BulkRow(
            rowNumber: rowNum,
            raw: row,
            status: RowStatus.updatePending,
            displayLabel: addonName,
            existingId: existingAddon['id'] as String,
          ));
        } else {
          result.add(BulkRow(
            rowNumber: rowNum,
            raw: row,
            status: RowStatus.skipped,
            skipReason: 'Already exists, no changes: "$addonName"',
            displayLabel: addonName,
          ));
        }
        continue;
      }

      result.add(BulkRow(
        rowNumber: rowNum,
        raw: row,
        status: RowStatus.valid,
        displayLabel: addonName,
      ));
    }

    return result;
  }

  @override
  Future<ImportResult> importRows(List<BulkRow> validRows) async {
    final client = Supabase.instance.client;

    int created = 0;
    int updated = 0;
    final failures = <({int row, String reason})>[];

    for (final br in validRows) {
      try {
        final row = br.raw;
        final isActive = _parseBool(row['is_active'], defaultVal: true);
        final description = (row['description'] ?? '').trim();
        final price = double.parse((row['price'] ?? '').trim());
        final name = (row['addon_name'] ?? '').trim();

        if (br.status == RowStatus.updatePending) {
          await client.from('addons').update({
            'price': price,
            'is_active': isActive,
            'description': description.isNotEmpty ? description : null,
          }).eq('id', br.existingId!);
          updated++;
        } else {
          await client.from('addons').insert({
            'name': name,
            'price': price,
            'is_active': isActive,
            if (description.isNotEmpty) 'description': description,
          });
          created++;
        }
      } catch (e) {
        failures.add((row: br.rowNumber, reason: e.toString()));
      }
    }

    return ImportResult(
      created: created,
      updated: updated,
      skipped: 0,
      failed: failures.length,
      failures: failures,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Returns a map keyed by lowercase addon name → full row including `id`.
  Future<Map<String, Map<String, dynamic>>> _loadExistingAddons(
      SupabaseClient client) async {
    final rows =
        await client.from('addons').select('id, name, price, description, is_active');
    return {
      for (final r in rows as List)
        (r['name'] as String).toLowerCase():
            Map<String, dynamic>.from(r as Map),
    };
  }

  bool _addonFieldsChanged(
      Map<String, String?> row, Map<String, dynamic> existing) {
    final newPrice = double.tryParse((row['price'] ?? '').trim());
    final dbPrice = (existing['price'] as num?)?.toDouble();
    if (newPrice != dbPrice) return true;

    final newActive = _parseBool(row['is_active'], defaultVal: true);
    if ((existing['is_active'] as bool? ?? true) != newActive) return true;

    final newDesc = (row['description'] ?? '').trim();
    final dbDesc = ((existing['description'] as String?) ?? '').trim();
    if (newDesc != dbDesc) return true;

    return false;
  }

  bool _parseBool(String? val, {required bool defaultVal}) {
    if (val == null || val.isEmpty) return defaultVal;
    final v = val.trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    return defaultVal;
  }
}
