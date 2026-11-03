import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

Future<void> downloadPdf(Uint8List bytes, String filename) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

Future<void> downloadPdfFromUrl(String url, String filename) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    await Printing.sharePdf(bytes: response.bodyBytes, filename: filename);
  }
}
