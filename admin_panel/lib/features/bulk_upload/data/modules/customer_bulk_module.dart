import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../bulk_upload_module.dart';
import '../../models/bulk_row.dart';
import '../excel_utils.dart' as xu;

class CustomerBulkModule extends BulkUploadModule {
  @override
  String get moduleTitle => 'Customers';

  @override
  String get templateFilename => 'customers_template.xlsx';

  @override
  List<String> get templateColumns => [
        'full_name',
        'phone',
        'email',
        'is_active',
        'address_line_1',
        'area',
        'city',
        'state',
        'pincode',
        'landmark',
      ];

  @override
  List<List<String>> get exampleRows => [
        [
          'Aarav Sharma',
          '9876543210',
          'aarav@example.com',
          'TRUE',
          '12 MG Road',
          'Koramangala',
          'Bangalore',
          'Karnataka',
          '560034',
          'Near Metro',
        ],
        [
          'Priya Patel',
          '9123456780',
          'priya@example.com',
          'TRUE',
          '',
          '',
          '',
          '',
          '',
          '',
        ],
      ];

  @override
  String get instructionsText => '''CUSTOMERS BULK UPLOAD — Instructions

Required columns:
  full_name  : Customer's full name
  phone      : Mobile number (used for duplicate detection)
  email      : Email address

Optional columns:
  is_active       : TRUE or FALSE (default TRUE)
  address_line_1  : Street address
  area            : Area / locality (becomes address_line_2)
  city            : City
  state           : State
  pincode         : PIN code
  landmark        : Nearby landmark

Duplicate handling:
  A customer with the same phone and identical core fields is SKIPPED.
  If the phone matches but full_name, email, or is_active differs, the record is UPDATED.
  Address fields are not compared or updated on existing customers.
  Duplicate phone numbers within the uploaded file are SKIPPED after the first occurrence.

Notes:
  - Leave address columns blank to create the customer without an address.
  - Do not edit the column headers in row 1.
  - Keep this file as .xlsx format.''';

  @override
  List<Map<String, String?>> parseXlsx(Uint8List bytes) => xu.parseXlsx(bytes);

  @override
  Future<List<BulkRow>> validateRows(List<Map<String, String?>> rawRows) async {
    final client = Supabase.instance.client;
    final existing = await _loadExistingCustomers(client);

    final seenPhones = <String>{};

    return List.generate(rawRows.length, (i) {
      final row = rawRows[i];
      final rowNum = i + 2;
      final errors = <String>[];

      final name = (row['full_name'] ?? '').trim();
      final phone = (row['phone'] ?? '').trim();
      final email = (row['email'] ?? '').trim();

      if (name.isEmpty) errors.add('full_name is required');
      if (phone.isEmpty) errors.add('phone is required');
      if (email.isEmpty) errors.add('email is required');

      if (errors.isNotEmpty) {
        return BulkRow(
          rowNumber: rowNum,
          raw: row,
          status: RowStatus.invalid,
          errors: errors,
          displayLabel: name.isNotEmpty ? name : phone,
        );
      }

      // Within-upload duplicate.
      if (seenPhones.contains(phone)) {
        return BulkRow(
          rowNumber: rowNum,
          raw: row,
          status: RowStatus.skipped,
          skipReason: 'Duplicate phone in this upload: $phone',
          displayLabel: name,
        );
      }
      seenPhones.add(phone);

      final existingCustomer = existing[phone];
      if (existingCustomer != null) {
        if (_customerFieldsChanged(row, existingCustomer)) {
          return BulkRow(
            rowNumber: rowNum,
            raw: row,
            status: RowStatus.updatePending,
            displayLabel: name,
            existingId: existingCustomer['id'] as String,
          );
        }
        return BulkRow(
          rowNumber: rowNum,
          raw: row,
          status: RowStatus.skipped,
          skipReason: 'Already exists, no changes: $phone',
          displayLabel: name,
        );
      }

      return BulkRow(
        rowNumber: rowNum,
        raw: row,
        status: RowStatus.valid,
        displayLabel: name,
      );
    });
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
        final name = (row['full_name'] ?? '').trim();
        final email = (row['email'] ?? '').trim();

        if (br.status == RowStatus.updatePending) {
          // Only update core customer fields; address rows are not modified.
          await client.from('customers').update({
            'full_name': name,
            'email': email,
            'is_active': isActive,
          }).eq('id', br.existingId!);
          updated++;
        } else {
          final result = await client
              .from('customers')
              .insert({
                'full_name': name,
                'phone': (row['phone'] ?? '').trim(),
                'email': email,
                'is_active': isActive,
              })
              .select('id')
              .single();

          final customerId = result['id'] as String;

          final line1 = (row['address_line_1'] ?? '').trim();
          final area = (row['area'] ?? '').trim();
          final city = (row['city'] ?? '').trim();
          final state = (row['state'] ?? '').trim();
          final pincode = (row['pincode'] ?? '').trim();
          final landmark = (row['landmark'] ?? '').trim();

          if (line1.isNotEmpty || city.isNotEmpty) {
            String line2 = area;
            if (landmark.isNotEmpty) {
              line2 = line2.isNotEmpty ? '$line2, Near $landmark' : 'Near $landmark';
            }
            await client.from('customer_addresses').insert({
              'customer_id': customerId,
              'address_type': 'Home',
              'address_line_1': line1.isNotEmpty ? line1 : city,
              if (line2.isNotEmpty) 'address_line_2': line2,
              'city': city,
              'state': state,
              'pincode': pincode,
              'is_default': true,
            });
          }

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

  /// Returns a map keyed by phone → customer row including `id`.
  Future<Map<String, Map<String, dynamic>>> _loadExistingCustomers(
      SupabaseClient client) async {
    final rows = await client
        .from('customers')
        .select('id, phone, full_name, email, is_active');
    return {
      for (final r in rows as List)
        (r['phone'] as String).trim(): Map<String, dynamic>.from(r as Map),
    };
  }

  bool _customerFieldsChanged(
      Map<String, String?> row, Map<String, dynamic> existing) {
    final newName = (row['full_name'] ?? '').trim();
    if (newName != ((existing['full_name'] as String?) ?? '')) return true;

    final newEmail = (row['email'] ?? '').trim();
    if (newEmail != ((existing['email'] as String?) ?? '')) return true;

    final newActive = _parseBool(row['is_active'], defaultVal: true);
    if ((existing['is_active'] as bool? ?? true) != newActive) return true;

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
