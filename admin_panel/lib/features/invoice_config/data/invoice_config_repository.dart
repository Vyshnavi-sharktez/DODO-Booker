import 'package:supabase_flutter/supabase_flutter.dart';

class InvoiceConfigData {
  final String? id;
  final String companyName;
  final String companyTagline;
  final String? companyAddress;
  final String? companyGstin;
  final String? companyPhone;
  final String? companyEmail;
  final String? logoUrl;
  final String invoicePrefix;
  final String? footerNote;
  final String? templatePdfUrl;
  final String? templatePdfName;

  const InvoiceConfigData({
    this.id,
    required this.companyName,
    required this.companyTagline,
    this.companyAddress,
    this.companyGstin,
    this.companyPhone,
    this.companyEmail,
    this.logoUrl,
    required this.invoicePrefix,
    this.footerNote,
    this.templatePdfUrl,
    this.templatePdfName,
  });

  factory InvoiceConfigData.defaults() => const InvoiceConfigData(
        companyName: 'DODO BOOKER',
        companyTagline: 'Home Services Platform',
        invoicePrefix: 'INV',
      );

  factory InvoiceConfigData.fromMap(Map<String, dynamic> m) => InvoiceConfigData(
        id: m['id'] as String?,
        companyName: (m['company_name'] as String?) ?? 'DODO BOOKER',
        companyTagline: (m['company_tagline'] as String?) ?? 'Home Services Platform',
        companyAddress: m['company_address'] as String?,
        companyGstin: m['company_gstin'] as String?,
        companyPhone: m['company_phone'] as String?,
        companyEmail: m['company_email'] as String?,
        logoUrl: m['logo_url'] as String?,
        invoicePrefix: (m['invoice_prefix'] as String?) ?? 'INV',
        footerNote: m['footer_note'] as String?,
        templatePdfUrl: m['template_pdf_url'] as String?,
        templatePdfName: m['template_pdf_name'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'company_name': companyName,
        'company_tagline': companyTagline,
        'company_address': companyAddress,
        'company_gstin': companyGstin,
        'company_phone': companyPhone,
        'company_email': companyEmail,
        'logo_url': logoUrl,
        'invoice_prefix': invoicePrefix,
        'footer_note': footerNote,
        'template_pdf_url': templatePdfUrl,
        'template_pdf_name': templatePdfName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class InvoiceConfigRepository {
  const InvoiceConfigRepository(this._client);
  final SupabaseClient _client;

  Future<InvoiceConfigData> fetch() async {
    final rows = await _client.from('invoice_config').select().limit(1);
    if (rows.isEmpty) return InvoiceConfigData.defaults();
    return InvoiceConfigData.fromMap(rows.first);
  }

  Future<void> save(InvoiceConfigData config) async {
    final payload = config.toMap();
    if (config.id != null) {
      await _client.from('invoice_config').update(payload).eq('id', config.id!);
    } else {
      await _client.from('invoice_config').insert(payload);
    }
  }
}
