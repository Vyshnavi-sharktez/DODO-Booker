import 'dart:io';

Future<void> downloadCsv(String csvContent, String filename) async {
  final file = File(filename);
  await file.writeAsString(csvContent);
}
