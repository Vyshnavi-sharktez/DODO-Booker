import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/booking.dart';

class InvoiceRecord {
  final String invoiceNumber;
  final String pdfPath;
  final double? subtotal;
  final double? taxAmount;
  final double? discountAmount;
  final double? totalAmount;

  const InvoiceRecord({
    required this.invoiceNumber,
    required this.pdfPath,
    this.subtotal,
    this.taxAmount,
    this.discountAmount,
    this.totalAmount,
  });
}

class InvoiceStorageService {
  InvoiceStorageService._();

  static final _client = Supabase.instance.client;
  static const _bucket = 'invoices';

  static Future<InvoiceRecord?> fetchExisting(String bookingId) async {
    final row = await _client
        .from('invoices')
        .select()
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (row == null) return null;
    return InvoiceRecord(
      invoiceNumber: row['invoice_number'] as String,
      pdfPath: row['pdf_path'] as String,
      subtotal: (row['subtotal'] as num?)?.toDouble(),
      taxAmount: (row['tax_amount'] as num?)?.toDouble(),
      discountAmount: (row['discount_amount'] as num?)?.toDouble(),
      totalAmount: (row['total_amount'] as num?)?.toDouble(),
    );
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
    required Booking booking,
    String generatedBy = 'admin',
  }) async {
    await _client.from('invoices').insert({
      'booking_id': bookingId,
      'invoice_number': invoiceNumber,
      'pdf_path': pdfPath,
      'subtotal': booking.subtotal,
      'tax_amount': booking.taxAmount,
      'discount_amount': booking.discountAmount,
      'total_amount': booking.totalAmount,
      'generated_by': generatedBy,
    });
  }

  static Future<String> createSignedUrl(String path) async {
    return await _client.storage
        .from(_bucket)
        .createSignedUrl(path, 3600);
  }

  static Future<void> handleRaceConditionInsert({
    required String bookingId,
    required String invoiceNumber,
    required String pdfPath,
    required Booking booking,
    String generatedBy = 'admin',
  }) async {
    try {
      await insertRecord(
        bookingId: bookingId,
        invoiceNumber: invoiceNumber,
        pdfPath: pdfPath,
        booking: booking,
        generatedBy: generatedBy,
      );
    } catch (e) {
      // Concurrent generation — another request already inserted the record.
      debugPrint('[InvoiceStorage] Race condition on insert (ignored): $e');
    }
  }
}
