import 'package:file_picker/file_picker.dart';

export 'document_file_picker.dart' show PickedDocument;

import 'document_file_picker.dart';

/// Android / iOS / desktop implementation — delegates to file_picker.
Future<PickedDocument?> pickDocumentFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    withData: true,
  );
  if (result == null) return null;
  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null) return null;
  return PickedDocument(
    name: file.name,
    extension: file.extension ?? '',
    bytes: bytes,
  );
}
