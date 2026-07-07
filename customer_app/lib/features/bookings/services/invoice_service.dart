import 'dart:math';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../models/my_booking_model.dart';
import 'invoice_downloader.dart';
import '../../../models/profile_model.dart';

class InvoiceService {
  InvoiceService._();

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd MMM yyyy');

  // ── Public API ─────────────────────────────────────────────────────────────

  static Future<void> downloadInvoice({
    required MyBookingModel booking,
    required ProfileModel customer,
  }) async {
    final bytes = await _buildPdf(booking: booking, customer: customer);
    final num = _invoiceNumber(booking.id);
    await downloadPdf(bytes, 'DODO_$num.pdf');
  }

  // ── Invoice number ─────────────────────────────────────────────────────────

  static String _invoiceNumber(String bookingId) {
    final id = bookingId.replaceAll('-', '').toUpperCase();
    return 'INV-${id.substring(0, min(8, id.length))}';
  }

  // ── PDF builder ────────────────────────────────────────────────────────────

  static Future<Uint8List> _buildPdf({
    required MyBookingModel booking,
    required ProfileModel customer,
  }) async {
    final doc = pw.Document();
    final invNum = _invoiceNumber(booking.id);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        build: (ctx) => [
          _header(invNum, booking.createdAt),
          pw.SizedBox(height: 28),
          _infoSection(booking, customer),
          pw.SizedBox(height: 24),
          _itemsTable(booking),
          if (booking.addons.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _addonsTable(booking),
          ],
          pw.SizedBox(height: 20),
          _totalsBlock(
            subtotal: booking.baseAmount,
            taxes: booking.taxAmount,
            total: booking.totalAmount,
          ),
          pw.SizedBox(height: 28),
          _footer(),
        ],
      ),
    );

    return doc.save();
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  static pw.Widget _header(String invoiceNum, DateTime date) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('111111')),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'DODO BOOKER',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('D4AF37'),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Home Services Platform',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColor.fromHex('9AA0A6'),
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'TAX INVOICE',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                invoiceNum,
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColor.fromHex('D4AF37'),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                _dateFmt.format(date),
                style: pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bill-to + service details ──────────────────────────────────────────────

  static pw.Widget _infoSection(
      MyBookingModel booking, ProfileModel customer) {
    final addr = booking.address;
    final line2 =
        addr.line2 != null && addr.line2!.isNotEmpty ? addr.line2! : null;
    final cityLine = [addr.city, addr.state, addr.pincode]
        .where((s) => s.isNotEmpty)
        .join(', ');

    final assignedTo = booking.vendorName ??
        (booking.assignmentType == 'DODO Team' ? 'DODO Team' : null);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Bill to
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel('BILL TO'),
              pw.SizedBox(height: 6),
              if (customer.fullName.isNotEmpty)
                pw.Text(
                  customer.fullName,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 12),
                ),
              pw.SizedBox(height: 4),
              if (customer.mobileNumber.isNotEmpty)
                pw.Text(customer.mobileNumber,
                    style: const pw.TextStyle(fontSize: 11)),
              if (customer.email != null && customer.email!.isNotEmpty)
                pw.Text(customer.email!,
                    style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text(addr.line1, style: const pw.TextStyle(fontSize: 11)),
              if (line2 != null)
                pw.Text(line2, style: const pw.TextStyle(fontSize: 11)),
              if (cityLine.isNotEmpty)
                pw.Text(cityLine, style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
        pw.SizedBox(width: 32),
        // Service details
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel('SERVICE DETAILS'),
              pw.SizedBox(height: 6),
              _detailRow(
                'Booking ID',
                booking.id
                    .replaceAll('-', '')
                    .substring(0, min(8, booking.id.replaceAll('-', '').length))
                    .toUpperCase(),
              ),
              _detailRow('Date', _dateFmt.format(booking.scheduledDate)),
              _detailRow('Time', booking.timeSlot),
              if (assignedTo != null) _detailRow('Assigned To', assignedTo),
              _detailRow('Status', 'Completed'),
            ],
          ),
        ),
      ],
    );
  }

  // ── Items table ────────────────────────────────────────────────────────────

  static pw.Widget _itemsTable(MyBookingModel booking) {
    final items = booking.items;

    if (items.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel('SERVICES'),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border:
                  pw.Border.all(color: PdfColor.fromHex('E5E7EB'), width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(booking.serviceName,
                    style: const pw.TextStyle(fontSize: 11)),
                pw.Text(
                  _currency.format(booking.totalAmount),
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionLabel('SERVICES'),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromHex('E5E7EB'), width: 0.5),
          columnWidths: const {
            0: pw.FractionColumnWidth(0.05),
            1: pw.FractionColumnWidth(0.47),
            2: pw.FractionColumnWidth(0.08),
            3: pw.FractionColumnWidth(0.20),
            4: pw.FractionColumnWidth(0.20),
          },
          children: [
            pw.TableRow(
              decoration:
                  pw.BoxDecoration(color: PdfColor.fromHex('111111')),
              children: [
                _tableHeader('#'),
                _tableHeader('Service'),
                _tableHeader('Qty'),
                _tableHeader('Unit Price'),
                _tableHeader('Amount'),
              ],
            ),
            ...items.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: idx.isOdd
                      ? PdfColor.fromHex('F7F8FA')
                      : PdfColors.white,
                ),
                children: [
                  _tableCell('${idx + 1}', align: pw.Alignment.center),
                  _tableCell(item.serviceName),
                  _tableCell('${item.quantity}',
                      align: pw.Alignment.center),
                  _tableCell(
                    _currency.format(item.unitPrice),
                    align: pw.Alignment.centerRight,
                  ),
                  _tableCell(
                    _currency.format(item.totalPrice),
                    align: pw.Alignment.centerRight,
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  // ── Add-ons table ──────────────────────────────────────────────────────────

  static pw.Widget _addonsTable(MyBookingModel booking) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionLabel('ADD-ONS'),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromHex('E5E7EB'), width: 0.5),
          columnWidths: const {
            0: pw.FractionColumnWidth(0.65),
            1: pw.FractionColumnWidth(0.35),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('111111')),
              children: [
                _tableHeader('Add-on'),
                _tableHeader('Price'),
              ],
            ),
            ...booking.addons.asMap().entries.map((e) {
              final idx = e.key;
              final addon = e.value;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: idx.isOdd
                      ? PdfColor.fromHex('F7F8FA')
                      : PdfColors.white,
                ),
                children: [
                  _tableCell(addon.name),
                  _tableCell(
                    _currency.format(addon.price),
                    align: pw.Alignment.centerRight,
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  // ── Totals ─────────────────────────────────────────────────────────────────

  static pw.Widget _totalsBlock({
    required double subtotal,
    required double taxes,
    required double total,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 240,
          child: pw.Column(
            children: [
              _totalRow('Subtotal', _currency.format(subtotal)),
              if (taxes > 0) _totalRow('Taxes & Fees', _currency.format(taxes)),
              pw.Divider(color: PdfColor.fromHex('E5E7EB')),
              _totalRow(
                'Total Amount',
                _currency.format(total),
                bold: true,
                fontSize: 12,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  static pw.Widget _footer() {
    final grey = PdfColor.fromHex('5F6368');
    final lightGrey = PdfColor.fromHex('9AA0A6');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Divider(color: PdfColor.fromHex('E5E7EB')),
        pw.SizedBox(height: 8),
        pw.Text(
          'Payment details will be available after payment is processed.',
          style: pw.TextStyle(
              fontSize: 9, color: grey, fontStyle: pw.FontStyle.italic),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'This is a computer-generated invoice and does not require a physical signature.',
          style: pw.TextStyle(fontSize: 9, color: grey),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '© ${DateTime.now().year} DODO Booker. All rights reserved.',
          style: pw.TextStyle(fontSize: 9, color: lightGrey),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  static pw.Widget _sectionLabel(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('5F6368'),
        letterSpacing: 1.2,
      ),
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 76,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                  fontSize: 10, color: PdfColor.fromHex('5F6368')),
            ),
          ),
          pw.Text(': ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String amount, {
    bool bold = false,
    double fontSize = 10,
  }) {
    final style = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: bold
          ? PdfColor.fromHex('111111')
          : PdfColor.fromHex('5F6368'),
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(amount, style: style),
        ],
      ),
    );
  }
}
