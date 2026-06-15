// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

export 'document_file_picker.dart' show PickedDocument;

import 'document_file_picker.dart';

/// Flutter Web implementation — uses a hidden <input type="file"> element via
/// dart:html. Avoids the file_picker singleton initialization issue on Chrome.
Future<PickedDocument?> pickDocumentFile() async {
  final completer = Completer<PickedDocument?>();

  final input = html.FileUploadInputElement()
    ..accept = 'image/jpeg,image/png,image/webp,application/pdf'
    ..style.display = 'none';

  // Must be in the DOM for the click to be honoured by all browsers.
  html.document.body!.children.add(input);

  input.onChange.listen((event) async {
    try {
      final files = input.files;
      if (files == null || files.isEmpty) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final file = files.first;
      debugPrint('[FILE_PICKER_WEB] File selected : ${file.name}');
      debugPrint('[FILE_PICKER_WEB] File size     : ${file.size} bytes');

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      // Chrome returns the result as a NativeUint8List (Uint8List subtype),
      // not a ByteBuffer. Handle both to be safe.
      final raw = reader.result;
      debugPrint('[FILE_PICKER_WEB] FileReader result type: ${raw.runtimeType}');
      final Uint8List bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else {
        bytes = (raw as ByteBuffer).asUint8List();
      }
      debugPrint('[FILE_PICKER_WEB] Bytes read    : ${bytes.length}');

      final name = file.name;
      final ext =
          name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (!completer.isCompleted) {
        completer.complete(
          PickedDocument(name: name, extension: ext, bytes: bytes),
        );
      }
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    } finally {
      input.remove();
    }
  });

  input.click();

  return completer.future;
}
