import '../models/bulk_row.dart';

// Pure helper functions extracted from CatalogBulkModule so they can be unit-tested
// without a live Supabase connection. The module delegates to these functions; the
// functions themselves have no external dependencies.

/// Extracts non-empty level values (level_1, level_2, …) from a parsed row map.
/// Stops at the first blank/missing level so the result is always contiguous.
List<String> extractCatalogLevels(Map<String, String?> row) {
  final levels = <String>[];
  var n = 1;
  while (true) {
    final key = 'level_$n';
    final val = (row[key] ?? '').trim();
    if (val.isEmpty) break;
    levels.add(val);
    n++;
  }
  return levels;
}

/// Parses a cell string value as a boolean.
/// Accepts 'true'/'1'/'yes' (case-insensitive) as true, 'false'/'0'/'no' as false.
/// Returns [defaultVal] when the input is null, empty, or unrecognised.
bool parseCatalogBool(String? val, {required bool defaultVal}) {
  if (val == null || val.isEmpty) return defaultVal;
  final v = val.trim().toLowerCase();
  if (v == 'true' || v == '1' || v == 'yes') return true;
  if (v == 'false' || v == '0' || v == 'no') return false;
  return defaultVal;
}

/// Looks up a child node by [name] under [parentId] in the in-memory catalog cache.
/// Returns the node ID if found (case-insensitive), or null.
String? findCatalogChild(
  String? parentId,
  String name,
  Map<String?, List<String>> childrenOf,
  Map<String, Map<String, dynamic>> nodesById,
) {
  final children = childrenOf[parentId] ?? [];
  final lc = name.toLowerCase();
  for (final id in children) {
    final n = nodesById[id];
    if (n != null && (n['name'] as String?)?.toLowerCase() == lc) return id;
  }
  return null;
}

/// Returns true if any leaf-node field in [row] differs from [existing].
/// [existing] must contain all leaf fields (loaded by _loadCache).
bool catalogLeafFieldsChanged(
  Map<String, String?> row,
  Map<String, dynamic> existing,
) {
  final newBookable = parseCatalogBool(row['is_bookable'], defaultVal: false);
  if ((existing['is_bookable'] as bool? ?? false) != newBookable) return true;

  final newActive = parseCatalogBool(row['is_active'], defaultVal: true);
  if ((existing['is_active'] as bool? ?? true) != newActive) return true;

  final newPrice = double.tryParse((row['base_price'] ?? '').trim());
  final dbPrice = (existing['base_price'] as num?)?.toDouble();
  if (newPrice != dbPrice) return true;

  final newDuration = int.tryParse((row['estimated_duration'] ?? '').trim());
  final dbDuration = existing['estimated_duration'] as int?;
  if (newDuration != dbDuration) return true;

  final newMin = double.tryParse((row['minimum_order_amount'] ?? '').trim());
  final dbMin = (existing['minimum_order_amount'] as num?)?.toDouble();
  if (newMin != dbMin) return true;

  // Treat null and empty string as equivalent (import normalises empty → null).
  final newDesc = (row['description'] ?? '').trim();
  final dbDesc = ((existing['description'] as String?) ?? '').trim();
  if (newDesc != dbDesc) return true;

  final newIcon = (row['icon_key'] ?? '').trim();
  final dbIcon = ((existing['icon_key'] as String?) ?? '').trim();
  if (newIcon != dbIcon) return true;

  final newSort = int.tryParse((row['sort_order'] ?? '').trim()) ?? 0;
  final dbSort = existing['sort_order'] as int? ?? 0;
  if (newSort != dbSort) return true;

  return false;
}

/// Validates a single catalog row against the in-memory node cache.
///
/// [seenPaths] is a mutable set that tracks canonical paths already seen in
/// this upload batch (case-insensitive). The function adds the current path
/// to [seenPaths] when a row is not a within-upload duplicate, so repeated
/// calls with the same set detect duplicates within the uploaded file.
///
/// Does not touch Supabase. The caller is responsible for populating
/// [childrenOf] and [nodesById] (e.g. from a prior `_loadCache` call or
/// from test fixtures).
BulkRow validateCatalogRow({
  required Map<String, String?> row,
  required int rowNumber,
  required Map<String?, List<String>> childrenOf,
  required Map<String, Map<String, dynamic>> nodesById,
  required Set<String> seenPaths,
}) {
  final levels = extractCatalogLevels(row);

  if (levels.isEmpty) {
    return BulkRow(
      rowNumber: rowNumber,
      raw: row,
      status: RowStatus.invalid,
      errors: ['At least level_1 is required'],
    );
  }

  final isBookable = parseCatalogBool(row['is_bookable'], defaultVal: false);
  if (isBookable) {
    final priceStr = (row['base_price'] ?? '').trim();
    if (priceStr.isEmpty || double.tryParse(priceStr) == null) {
      return BulkRow(
        rowNumber: rowNumber,
        raw: row,
        status: RowStatus.invalid,
        errors: ['base_price is required and must be a number when is_bookable=TRUE'],
        displayLabel: levels.last,
      );
    }
  }

  // Walk the path; bail out early if any intermediate node is missing (the
  // leaf cannot possibly exist under an absent parent).
  String? parentId;
  String? existingLeafId;
  for (var idx = 0; idx < levels.length; idx++) {
    final name = levels[idx];
    final existingId = findCatalogChild(parentId, name, childrenOf, nodesById);
    if (idx == levels.length - 1) {
      existingLeafId = existingId;
    } else {
      if (existingId == null) break; // intermediate missing → leaf is new
      parentId = existingId;
    }
  }

  // Canonical path key for within-upload duplicate detection.
  final pathKey = levels.map((l) => l.toLowerCase()).join(' > ');
  if (seenPaths.contains(pathKey)) {
    return BulkRow(
      rowNumber: rowNumber,
      raw: row,
      status: RowStatus.skipped,
      skipReason: 'Duplicate path in this upload: "${levels.join(' > ')}"',
      displayLabel: levels.last,
    );
  }
  seenPaths.add(pathKey);

  if (existingLeafId != null) {
    final existing = nodesById[existingLeafId]!;
    if (catalogLeafFieldsChanged(row, existing)) {
      return BulkRow(
        rowNumber: rowNumber,
        raw: row,
        status: RowStatus.updatePending,
        displayLabel: levels.last,
        existingId: existingLeafId,
      );
    }
    return BulkRow(
      rowNumber: rowNumber,
      raw: row,
      status: RowStatus.skipped,
      skipReason: 'Already exists, no changes: "${levels.join(' > ')}"',
      displayLabel: levels.last,
    );
  }

  return BulkRow(
    rowNumber: rowNumber,
    raw: row,
    status: RowStatus.valid,
    displayLabel: levels.last,
  );
}
