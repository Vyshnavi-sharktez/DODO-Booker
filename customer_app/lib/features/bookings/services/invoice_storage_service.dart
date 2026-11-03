import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/my_booking_model.dart';

class CustomerInvoiceRecord {
  final String invoiceNumber;
  final String pdfPath;

  const CustomerInvoiceRecord({
    required this.invoiceNumber,
    required this.pdfPath,
  });
}

class CustomerInvoiceConfig {
  final String companyName;
  final String companyTagline;
  final String? companyGstin;
  final String? logoUrl;
  final String invoicePrefix;
  final String? footerNote;
  final String? templatePdfUrl;

  const CustomerInvoiceConfig({
    required this.companyName,
    required this.companyTagline,
    this.companyGstin,
    this.logoUrl,
    required this.invoicePrefix,
    this.footerNote,
    this.templatePdfUrl,
  });

  factory CustomerInvoiceConfig.defaults() => const CustomerInvoiceConfig(
        companyName: 'DODO BOOKER',
        companyTagline: 'Home Services Platform',
        invoicePrefix: 'INV',
      );

  factory CustomerInvoiceConfig.fromMap(Map<String, dynamic> m) =>
      CustomerInvoiceConfig(
        companyName: (m['company_name'] as String?) ?? 'DODO BOOKER',
        companyTagline:
            (m['company_tagline'] as String?) ?? 'Home Services Platform',
        companyGstin: m['company_gstin'] as String?,
        logoUrl: m['logo_url'] as String?,
        invoicePrefix: (m['invoice_prefix'] as String?) ?? 'INV',
        footerNote: m['footer_note'] as String?,
        templatePdfUrl: m['template_pdf_url'] as String?,
      );
}

class InvoiceStorageService {
  InvoiceStorageService._();

  static final _client = Supabase.instance.client;
  static const _bucket = 'invoices';

  static Future<CustomerInvoiceRecord?> fetchExisting(
      String bookingId) async {
    final row = await _client
        .from('invoices')
        .select('invoice_number, pdf_path')
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (row == null) return null;
    return CustomerInvoiceRecord(
      invoiceNumber: row['invoice_number'] as String,
      pdfPath: row['pdf_path'] as String,
    );
  }

  static Future<CustomerInvoiceConfig> fetchConfig() async {
    try {
      final rows = await _client
          .from('invoice_config')
          .select()
          .limit(1);
      if (rows.isNotEmpty) {
        return CustomerInvoiceConfig.fromMap(
            rows.first);
      }
    } catch (_) {}
    return CustomerInvoiceConfig.defaults();
  }

  static Future<String> nextInvoiceNumber(String prefix) async {
    final result = await _client
        .rpc('next_invoice_number', params: {'p_prefix': prefix});
    return result as String;
  }

  static Future<void> uploadPdf(String path, Uint8List bytes) async {
    await _client.storage.from(_bucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'application/pdf',
        upsert: true,
      ),
    );
  }

  static Future<void> insertRecord({
    required String bookingId,
    required String invoiceNumber,
    required String pdfPath,
    required MyBookingModel booking,
  }) async {
    try {
      await _client.from('invoices').insert({
        'booking_id': bookingId,
        'invoice_number': invoiceNumber,
        'pdf_path': pdfPath,
        'subtotal': booking.baseAmount,
        'tax_amount': booking.taxAmount,
        'total_amount': booking.totalAmount,
        'generated_by': 'customer',
      });
    } catch (e) {
      // Race condition: record already inserted by another request
      debugPrint('[InvoiceStorage] Race condition on insert (ignored): $e');
    }
  }

  static Future<String> createSignedUrl(String path) async {
    return await _client.storage
        .from(_bucket)
        .createSignedUrl(path, 3600);
  }
}
