import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> downloadXlsx(Uint8List bytes, String filename) async {
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save template as',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (savePath == null) return; // user cancelled — do nothing
  await File(savePath).writeAsBytes(bytes, flush: true);
}
