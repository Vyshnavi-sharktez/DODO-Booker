import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

/// Generates a downloadable .xlsx template using the excel package (encode only).
///
/// Sheet layout: "Template" sheet first, then "Instructions".
/// Sheet1 is deleted last (after other sheets exist) so the package's
/// "cannot delete the only sheet" guard does not silently skip the deletion.
Uint8List generateTemplate({
  required List<String> columns,
  required List<List<String>> exampleRows,
  required String instructions,
}) {
  final workbook = Excel.createExcel();

  final template = workbook['Template'];
  template.appendRow(columns.map<CellValue>(TextCellValue.new).toList());
  for (final row in exampleRows) {
    template.appendRow(row.map<CellValue>(TextCellValue.new).toList());
  }

  final inst = workbook['Instructions'];
  for (final line in instructions.split('\n')) {
    inst.appendRow([TextCellValue(line)]);
  }

  workbook.delete('Sheet1');

  final encoded = workbook.encode();
  if (encoded == null) throw Exception('Excel encode() returned null');
  return Uint8List.fromList(encoded);
}

/// Parses an xlsx file into rows keyed by header name (lowercase, trimmed).
///
/// Blank/empty cells produce a null value in the returned map.
/// Completely absent cells (no XML element at all) are also null.
///
/// This implementation reads the xlsx ZIP directly using archive + xml,
/// bypassing the excel package's decoder. The excel package contains null
/// assertions (!bang operators) throughout its parse path that crash on
/// dart2js when processing real Microsoft Excel files. Reading the XML
/// ourselves avoids all of those failure modes and gives us correct null
/// semantics for blank cells without any coercion to "".
///
/// Sheet selection priority:
///   1. Sheet named "Template"
///   2. First sheet whose header row contains "level_1"
///   3. First sheet in the workbook (fallback)
List<Map<String, String?>> parseXlsx(Uint8List bytes) {
  print('[BU:parse] ===START=== bytes=${bytes.length}');

  // ── 1. Unzip ──────────────────────────────────────────────────────────────
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
    print('[BU:parse] archive: ${archive.files.length} files');
  } catch (e, st) {
    print('[BU:parse] UNZIP THREW: $e\n$st');
    rethrow;
  }

  // ── 2. Shared string table (SST) ──────────────────────────────────────────
  // Positional list: one entry per <si> element, in document order, with NO
  // deduplication. Preserves the correct index for every cell reference even
  // when the file has identical string values stored at different positions.
  final sst = <String>[];
  try {
    final sstFile = archive.findFile('xl/sharedStrings.xml');
    if (sstFile != null) {
      sstFile.decompress();
      final doc = XmlDocument.parse(utf8.decode(sstFile.content));
      for (final si in doc.findAllElements('si')) {
        final buf = StringBuffer();
        for (final t in si.findAllElements('t')) {
          if (t.parentElement?.name.local == 'rPh') continue; // skip phonetic
          buf.write(t.innerText);
        }
        sst.add(buf.toString());
      }
      print('[BU:parse] sst: ${sst.length} entries');
    } else {
      print('[BU:parse] no sharedStrings.xml — all strings are inline');
    }
  } catch (e, st) {
    print('[BU:parse] SST parse THREW: $e\n$st');
    rethrow;
  }

  // ── 3. Workbook relationships: rId → worksheet archive path ───────────────
  final ridToPath = <String, String>{};
  final sheetEntries = <({String name, String? rId})>[];
  try {
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relsFile != null) {
      relsFile.decompress();
      final doc = XmlDocument.parse(utf8.decode(relsFile.content));
      for (final rel in doc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final type = rel.getAttribute('Type') ?? '';
        final target = rel.getAttribute('Target');
        if (id != null && target != null && type.endsWith('worksheet')) {
          ridToPath[id] = _wsPath(target);
        }
      }
    }
    print('[BU:parse] ridToPath: $ridToPath');

    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile != null) {
      wbFile.decompress();
      final doc = XmlDocument.parse(utf8.decode(wbFile.content));
      for (final sheet in doc.findAllElements('sheet')) {
        final name = sheet.getAttribute('name');
        // r:id is namespace-prefixed; match by local name 'id' regardless of prefix.
        final rId = _localAttr(sheet, 'id');
        if (name != null) sheetEntries.add((name: name, rId: rId));
      }
    }
    print('[BU:parse] sheets: ${sheetEntries.map((e) => e.name).toList()}');
  } catch (e, st) {
    print('[BU:parse] workbook parse THREW: $e\n$st');
    rethrow;
  }

  if (sheetEntries.isEmpty) {
    print('[BU:parse] no sheets found');
    return [];
  }

  // ── 4. Select worksheet and parse it ─────────────────────────────────────
  Map<int, Map<int, String?>>? rawRows;
  String? chosenName;

  // Priority 1: explicit "Template" sheet
  for (final e in sheetEntries) {
    if (e.name == 'Template' && e.rId != null) {
      final path = ridToPath[e.rId!];
      if (path != null) {
        rawRows = _parseWorksheet(archive, path, sst);
        chosenName = e.name;
        print('[BU:parse] sheet chosen by name: "Template"');
      }
      break;
    }
  }

  // Priority 2: first sheet whose header row contains 'level_1'
  if (rawRows == null) {
    for (final e in sheetEntries) {
      final rId = e.rId;
      if (rId == null) continue;
      final path = ridToPath[rId];
      if (path == null) continue;
      final parsed = _parseWorksheet(archive, path, sst);
      if (parsed.isNotEmpty) {
        final firstKey = (parsed.keys.toList()..sort()).first;
        if (parsed[firstKey]!.values
            .any((v) => v?.toLowerCase() == 'level_1')) {
          rawRows = parsed;
          chosenName = e.name;
          print('[BU:parse] sheet chosen by header scan: "${e.name}"');
          break;
        }
      }
    }
  }

  // Priority 3: first sheet fallback
  if (rawRows == null) {
    final first = sheetEntries.first;
    final rId = first.rId;
    if (rId != null) {
      final path = ridToPath[rId];
      if (path != null) {
        rawRows = _parseWorksheet(archive, path, sst);
        chosenName = first.name;
        print('[BU:parse] sheet chosen as fallback: "$chosenName"');
      }
    }
  }

  if (rawRows == null || rawRows.isEmpty) {
    print('[BU:parse] no data found');
    return [];
  }

  print('[BU:parse] sheet "$chosenName" — ${rawRows.length} raw rows (incl. header)');

  // ── 5. Build header list ──────────────────────────────────────────────────
  final sortedRowNums = rawRows.keys.toList()..sort();
  final headerRowNum = sortedRowNums.first;
  final headerCells = rawRows[headerRowNum]!;

  final maxCol = headerCells.keys.fold(0, (a, b) => a > b ? a : b);
  final headers = List.generate(
    maxCol + 1,
    (i) => (headerCells[i] ?? '').toLowerCase().trim(),
  );
  print('[BU:parse] headers: $headers');

  if (!headers.contains('level_1')) {
    print('[BU:parse] WARNING: "level_1" not in headers');
  }

  // ── 6. Build result rows ──────────────────────────────────────────────────
  final result = <Map<String, String?>>[];
  for (final rowNum in sortedRowNums.skip(1)) {
    final cells = rawRows[rowNum]!;
    if (cells.isEmpty) continue;

    final map = <String, String?>{};
    for (var ci = 0; ci < headers.length; ci++) {
      final h = headers[ci];
      if (h.isEmpty) continue;
      map[h] = cells[ci]; // null when cell is blank
    }

    if (map.values.every((v) => v == null || v.isEmpty)) continue;
    result.add(map);
  }

  print('[BU:parse] ===DONE=== ${result.length} data rows');
  return result;
}

// ── Private helpers ───────────────────────────────────────────────────────────

/// Converts a worksheet relationship target to an archive-relative file path.
String _wsPath(String target) {
  if (target.startsWith('/')) return target.substring(1); // absolute → relative
  if (target.startsWith('xl/')) return target;
  return 'xl/$target'; // relative to xl/
}

/// Returns the value of the first attribute whose XML local name matches [local].
/// Handles namespace-prefixed attributes safely (e.g. r:id → local='id').
String? _localAttr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

/// Parses a worksheet file into {1-based rowNum → {0-based colIdx → value}}.
/// Blank cells are absent from the inner map (access returns null naturally).
Map<int, Map<int, String?>> _parseWorksheet(
  Archive archive,
  String path,
  List<String> sst,
) {
  final file = archive.findFile(path);
  if (file == null) {
    print('[BU:parse] worksheet not found in archive: $path');
    return {};
  }
  file.decompress();

  XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(file.content));
  } catch (e) {
    print('[BU:parse] worksheet XML parse error ($path): $e');
    return {};
  }

  final result = <int, Map<int, String?>>{};
  final sheetData = doc.findAllElements('sheetData').firstOrNull;
  if (sheetData == null) return result;

  for (final rowEl in sheetData.findElements('row')) {
    final rStr = rowEl.getAttribute('r');
    final rowIdx = rStr != null ? int.tryParse(rStr) : null;
    if (rowIdx == null) continue;

    final colMap = <int, String?>{};
    for (final cellEl in rowEl.findElements('c')) {
      final ref = cellEl.getAttribute('r');
      if (ref == null) continue;
      final colLetters =
          ref.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
      if (colLetters.isEmpty) continue;
      colMap[_colIndex(colLetters)] = _cellValue(cellEl, sst);
    }

    if (colMap.isNotEmpty) result[rowIdx] = colMap;
  }

  return result;
}

/// Converts column letter(s) to a 0-based column index.
/// A=0, B=1, Z=25, AA=26, AB=27, …
int _colIndex(String col) {
  var n = 0;
  for (final c in col.codeUnits) {
    n = n * 26 + (c - 64); // 'A'=65, so c-64 = 1-based position
  }
  return n - 1;
}

/// Extracts a cell's string value. Returns null for blank/empty cells.
String? _cellValue(XmlElement cell, List<String> sst) {
  final type = cell.getAttribute('t');

  switch (type) {
    case 's': // Shared string index
      final raw = cell.findElements('v').firstOrNull?.innerText.trim();
      if (raw == null || raw.isEmpty) return null;
      final idx = int.tryParse(raw);
      if (idx == null || idx >= sst.length) return null;
      final s = sst[idx];
      return s.isEmpty ? null : s;

    case 'inlineStr': // Inline string
      final buf = StringBuffer();
      for (final t in cell.findAllElements('t')) {
        buf.write(t.innerText);
      }
      final s = buf.toString();
      return s.isEmpty ? null : s;

    case 'b': // Boolean
      final raw = cell.findElements('v').firstOrNull?.innerText.trim();
      if (raw == null) return null;
      return raw == '1' ? 'TRUE' : 'FALSE';

    case 'str': // Formula-result string
    case 'e': // Error value
      final raw = cell.findElements('v').firstOrNull?.innerText.trim();
      return (raw == null || raw.isEmpty) ? null : raw;

    default: // Numeric (type='n' or absent), including formula-cached numbers
      final raw = cell.findElements('v').firstOrNull?.innerText.trim();
      if (raw == null || raw.isEmpty) return null;
      final d = double.tryParse(raw);
      if (d != null && d == d.truncateToDouble()) return d.toInt().toString();
      return raw;
  }
}
