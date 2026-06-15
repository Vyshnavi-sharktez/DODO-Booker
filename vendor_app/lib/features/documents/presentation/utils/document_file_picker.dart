import 'dart:typed_data';

/// Represents a file selected by the user, normalized across platforms.
class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.extension,
    required this.bytes,
  });

  final String name;
  final String extension;
  final Uint8List bytes;
}

/// Stub — replaced at compile time by the platform-specific implementation via
/// conditional imports in callers:
///
/// ```dart
/// import 'document_file_picker.dart'
///     if (dart.library.html) 'document_file_picker_web.dart'
///     if (dart.library.io)   'document_file_picker_mobile.dart';
/// ```
Future<PickedDocument?> pickDocumentFile() =>
    throw UnsupportedError('pickDocumentFile: no platform implementation');
