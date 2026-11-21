import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

const _channel = MethodChannel('com.dodobookerapp.customer/file_saver');

Future<void> downloadPdf(Uint8List bytes, String filename) async {
  if (Platform.isAndroid) {
    await _channel.invokeMethod<void>('saveToDownloads', {
      'bytes': bytes,
      'filename': filename,
    });
  } else if (Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
  } else {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}

Future<void> downloadPdfFromUrl(String url, String filename) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    await downloadPdf(response.bodyBytes, filename);
  }
}
