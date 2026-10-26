import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../vendors/data/vendors_repository.dart';
import '../../bulk_upload_module.dart';
import '../../models/bulk_row.dart';
import '../excel_utils.dart' as xu;

class VendorBulkModule extends BulkUploadModule {
  @override
  String get moduleTitle => 'Vendors';

  @override
  String get templateFilename => 'vendors_template.xlsx';

  @override
  List<String> get templateColumns => [
        'business_name',
        'owner_name',
        'phone',
        'email',
        'city',
        'address',
        'status',
        'is_active',
        'commission_rate',
        'preferred_vendor_fee',
      ];

  @override
  List<List<String>> get exampleRows => [
        [
          'Sparkle Cleaners',
          'Rahul Verma',
          '9988776655',
          'sparkle@example.com',
          'Mumbai',
          '5 Andheri West',
          'active',
          'TRUE',
          '15',
          '0',
        ],
        [
          'Pro Fix Services',
          '',
          '9876001122',
          'profix@example.com',
          'Delhi',
          '',
          'pending',
          'TRUE',
          '10',
          '100',
        ],
      ];

  @override
  String get instructionsText => '''VENDORS BULK UPLOAD — Instructions

Required columns:
  business_name : Vendor business name
  phone         : Mobile number (used for duplicate detection)
  email         : Contact email
  city          : Primary city of operation

Optional columns:
  owner_name          : Owner / contact person name
  address             : Street address
  status              : active | inactive | pending (default: pending)
  is_active           : TRUE or FALSE (default TRUE)
  commission_rate     : % commission (default 0)
  preferred_vendor_fee: Extra fee when selected as preferred vendor (default 0)

Duplicate handling:
  A vendor with the same phone and identical fields is SKIPPED.
  If the phone matches but any field differs, the existing record is UPDATED.
  Duplicate phone numbers within the uploaded file are SKIPPED after the first occurrence.

Notes:
  - Do not edit the column headers in row 1.
  - Keep this file as .xlsx format.''';

  @override
  List<Map<String, String?>> parseXlsx(Uint8List bytes) => xu.parseXlsx(bytes);

  @override
  Future<List<BulkRow>> validateRows(List<Map<String, String?>> rawRows) async {
    final client = Supabase.instance.client;
    final existing = await _loadExistingVendors(client);

    final seenPhones = <String>{};

    return List.generate(rawRows.length, (i) {
      final row = rawRows[i];
      final rowNum = i + 2;
      final errors = <String>[];

      final name = (row['business_name'] ?? '').trim();
      final phone = (row['phone'] ?? '').trim();
      final email = (row['email'] ?? '').trim();
      final city = (row['city'] ?? '').trim();

      if (name.isEmpty) errors.add('business_name is required');
      if (phone.isEmpty) errors.add('phone is required');
      if (email.isEmpty) errors.add('email is required');
      if (city.isEmpty) errors.add('city is required');

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

      final existingVendor = existing[phone];
      if (existingVendor != null) {
        if (_vendorFieldsChanged(row, existingVendor)) {
          return BulkRow(
            rowNumber: rowNum,
            raw: row,
            status: RowStatus.updatePending,
            displayLabel: name,
            existingId: existingVendor['id'] as String,
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
    final repo = VendorsRepository(client);
    int created = 0;
    int updated = 0;
    final failures = <({int row, String reason})>[];

    for (final br in validRows) {
      try {
        final row = br.raw;
        final isActive = _parseBool(row['is_active'], defaultVal: true);
        final statusRaw = (row['status'] ?? '').trim();
        final status = statusRaw.isEmpty ? 'pending' : statusRaw;
        final commission = double.tryParse(row['commission_rate'] ?? '') ?? 0.0;
        final pvFee = double.tryParse(row['preferred_vendor_fee'] ?? '') ?? 0.0;
        final ownerName = (row['owner_name'] ?? '').trim();
        final address = (row['address'] ?? '').trim();

        if (br.status == RowStatus.updatePending) {
          await client.from('vendors').update({
            'business_name': (row['business_name'] ?? '').trim(),
            'owner_name': ownerName.isNotEmpty ? ownerName : null,
            'email': (row['email'] ?? '').trim(),
            'city': (row['city'] ?? '').trim(),
            'address': address.isNotEmpty ? address : null,
            'status': status,
            'is_active': isActive,
            'commission_rate': commission,
            'preferred_vendor_fee': pvFee,
            'is_preferred_vendor': pvFee > 0,
          }).eq('id', br.existingId!);
          updated++;
        } else {
          await repo.createVendor(
            businessName: (row['business_name'] ?? '').trim(),
            ownerName: ownerName.isNotEmpty ? ownerName : null,
            phone: (row['phone'] ?? '').trim(),
            email: (row['email'] ?? '').trim(),
            city: (row['city'] ?? '').trim(),
            address: address.isNotEmpty ? address : null,
            status: status,
            isActive: isActive,
            commissionRate: commission,
            isPreferredVendor: pvFee > 0,
            preferredVendorFee: pvFee,
          );
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

  /// Returns a map keyed by phone → full vendor row including `id`.
  Future<Map<String, Map<String, dynamic>>> _loadExistingVendors(
      SupabaseClient client) async {
    final rows = await client.from('vendors').select(
      'id, phone, business_name, owner_name, email, city, address, '
      'status, is_active, commission_rate, preferred_vendor_fee',
    );
    return {
      for (final r in rows as List)
        (r['phone'] as String).trim(): Map<String, dynamic>.from(r as Map),
    };
  }

  bool _vendorFieldsChanged(
      Map<String, String?> row, Map<String, dynamic> existing) {
    final fields = <String, dynamic>{
      'business_name': (row['business_name'] ?? '').trim(),
      'owner_name': (row['owner_name'] ?? '').trim(),
      'email': (row['email'] ?? '').trim(),
      'city': (row['city'] ?? '').trim(),
      'address': (row['address'] ?? '').trim(),
      'status': (row['status'] ?? '').trim().isEmpty
          ? 'pending'
          : (row['status'] ?? '').trim(),
    };

    // String fields (null == empty).
    for (final key in ['business_name', 'email', 'city', 'status']) {
      if (fields[key] != ((existing[key] as String?) ?? '')) return true;
    }
    for (final key in ['owner_name', 'address']) {
      final newVal = fields[key] as String;
      final dbVal = ((existing[key] as String?) ?? '').trim();
      if (newVal != dbVal) return true;
    }

    final newActive = _parseBool(row['is_active'], defaultVal: true);
    if ((existing['is_active'] as bool? ?? true) != newActive) return true;

    final newCommission = double.tryParse(row['commission_rate'] ?? '') ?? 0.0;
    final dbCommission = (existing['commission_rate'] as num?)?.toDouble() ?? 0.0;
    if (newCommission != dbCommission) return true;

    final newPvFee = double.tryParse(row['preferred_vendor_fee'] ?? '') ?? 0.0;
    final dbPvFee =
        (existing['preferred_vendor_fee'] as num?)?.toDouble() ?? 0.0;
    if (newPvFee != dbPvFee) return true;

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
