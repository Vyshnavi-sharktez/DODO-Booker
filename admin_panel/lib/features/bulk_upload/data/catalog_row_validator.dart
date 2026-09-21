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

/// Validates a single catalog row against the in-memory node cache.
///
/// Does not touch Supabase. The caller is responsible for populating
/// [childrenOf] and [nodesById] (e.g. from a prior `_loadCache` call or
/// from test fixtures).
BulkRow validateCatalogRow({
  required Map<String, String?> row,
  required int rowNumber,
  required Map<String?, List<String>> childrenOf,
  required Map<String, Map<String, dynamic>> nodesById,
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

  // Walk the path to check whether the leaf already exists.
  String? parentId;
  for (var idx = 0; idx < levels.length; idx++) {
    final name = levels[idx];
    final existingId = findCatalogChild(parentId, name, childrenOf, nodesById);
    if (idx == levels.length - 1) {
      if (existingId != null) {
        return BulkRow(
          rowNumber: rowNumber,
          raw: row,
          status: RowStatus.skipped,
          skipReason: 'Node "${levels.join(' > ')}" already exists',
          displayLabel: levels.last,
        );
      }
    } else {
      parentId = existingId;
    }
  }

  return BulkRow(
    rowNumber: rowNumber,
    raw: row,
    status: RowStatus.valid,
    displayLabel: levels.last,
  );
}
