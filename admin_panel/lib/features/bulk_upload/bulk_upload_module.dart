import 'dart:typed_data';
import 'models/bulk_row.dart';

abstract class BulkUploadModule {
  String get moduleTitle;
  String get templateFilename;

  List<String> get templateColumns;
  List<List<String>> get exampleRows;
  String get instructionsText;

  Future<List<BulkRow>> validateRows(List<Map<String, String?>> rawRows);
  Future<ImportResult> importRows(List<BulkRow> validRows);

  /// Parses an uploaded xlsx file into raw string maps keyed by header name.
  /// Blank cells produce a null value; missing cells are absent from the map.
  List<Map<String, String?>> parseXlsx(Uint8List bytes);
}
