import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../bulk_upload_module.dart';
import '../../models/bulk_row.dart';
import '../excel_utils.dart' as xu;

class CatalogBulkModule extends BulkUploadModule {
  // In-memory catalog snapshot used across validate + import within one session.
  Map<String, Map<String, dynamic>>? _nodesById;
  // Maps parentId (null = root) → list of child node IDs.
  Map<String?, List<String>>? _childrenOf;

  @override
  String get moduleTitle => 'Catalog';

  @override
  String get templateFilename => 'catalog_template.xlsx';

  @override
  List<String> get templateColumns => [
        'level_1',
        'level_2',
        'level_3',
        'level_4',
        'level_5',
        'is_bookable',
        'base_price',
        'estimated_duration',
        'minimum_order_amount',
        'description',
        'icon_key',
        'sort_order',
        'is_active',
      ];

  @override
  List<List<String>> get exampleRows => [
        // Root category only
        ['AC Services', '', '', '', '', 'FALSE', '', '', '', 'Air conditioner services', '', '1', 'TRUE'],
        // Two-level: category → bookable service
        ['AC Services', 'AC Repair', '', '', '', 'TRUE', '299', '60', '199', 'AC repair and servicing', 'ac_repair', '1', 'TRUE'],
        // Three-level path
        ['Home Cleaning', 'Deep Cleaning', 'Kitchen Deep Clean', '', '', 'TRUE', '499', '90', '299', '', '', '1', 'TRUE'],
      ];

  @override
  String get instructionsText => '''CATALOG BULK UPLOAD — Instructions

Hierarchy columns (level_1 … level_5):
  Fill levels left-to-right to define the catalog path.
  Leave trailing levels blank for the current depth.
  Example: level_1=AC Services, level_2=AC Repair → creates "AC Repair" under "AC Services".

Leaf-node columns (applied to the deepest filled level):
  is_bookable           : TRUE = service customers can book; FALSE = category node (default FALSE)
  base_price            : Starting price in ₹ (required if is_bookable=TRUE)
  estimated_duration    : Duration in minutes (e.g. 60)
  minimum_order_amount  : Minimum order in ₹
  description           : Short description
  icon_key              : Icon identifier string
  sort_order            : Display order (default 0)
  is_active             : TRUE or FALSE (default TRUE)

Intermediate nodes:
  If a parent path node does not exist, it is created automatically as a
  non-bookable category with is_active=TRUE.

Duplicate handling:
  If a node with the exact path already exists, the row is SKIPPED.

Notes:
  - Column headers in row 1 must not be changed.
  - Dynamic levels: you may extend to level_6, level_7, etc. by adding more columns.
  - Keep this file as .xlsx format.''';

  @override
  List<Map<String, String?>> parseXlsx(Uint8List bytes) => xu.parseXlsx(bytes);

  // ── Cache management ──────────────────────────────────────────────────────────

  Future<void> _loadCache(SupabaseClient client) async {
    debugPrint('[CatalogBulk] _loadCache: querying catalog_nodes + relationships');
    final nodes = await client.from('catalog_nodes').select('id, name');
    final rels = await client.from('catalog_node_relationships').select('parent_id, child_id');
    debugPrint('[CatalogBulk] _loadCache: ${(nodes as List).length} nodes, ${(rels as List).length} rels');

    final nodesById = <String, Map<String, dynamic>>{};
    for (final n in nodes as List) {
      // Guard against unexpected nulls in DB response.
      final id = n['id'] as String?;
      if (id == null) {
        debugPrint('[CatalogBulk] Warning: node with null id skipped: $n');
        continue;
      }
      nodesById[id] = Map<String, dynamic>.from(n as Map);
    }

    final allChildIds = <String>{};
    final childrenOf = <String?, List<String>>{};
    for (final r in rels as List) {
      // parent_id IS nullable here: cast to String? not String.
      // Any null parent_id means the row was inserted outside the normal flow;
      // we skip it rather than crashing on the cast.
      final parentId = r['parent_id'] as String?;
      final childId = r['child_id'] as String?;
      if (childId == null) {
        debugPrint('[CatalogBulk] Warning: relationship with null child_id skipped: $r');
        continue;
      }
      allChildIds.add(childId);
      (childrenOf[parentId] ??= []).add(childId);
    }

    // Root nodes = nodes not appearing as any child.
    childrenOf[null] = nodesById.keys.where((id) => !allChildIds.contains(id)).toList();
    debugPrint('[CatalogBulk] _loadCache done: ${nodesById.length} nodes, ${childrenOf[null]?.length} roots');

    _nodesById = nodesById;
    _childrenOf = childrenOf;
  }

  String? _findChild(String? parentId, String name) {
    // Null-safe access — no ! operators. Both maps are set by _loadCache before
    // _findChild is ever called, but we guard anyway to avoid dart2js crashes.
    final childMap = _childrenOf;
    final nodeMap = _nodesById;
    if (childMap == null || nodeMap == null) return null;
    final children = childMap[parentId] ?? [];
    final lc = name.toLowerCase();
    for (final id in children) {
      final n = nodeMap[id];
      if (n != null && (n['name'] as String?)?.toLowerCase() == lc) return id;
    }
    return null;
  }

  void _addToCache(String? parentId, String nodeId, String name) {
    final nm = _nodesById;
    final cm = _childrenOf;
    if (nm == null || cm == null) return; // both set by _loadCache before importRows
    nm[nodeId] = {'id': nodeId, 'name': name};
    (cm[parentId] ??= []).add(nodeId);
  }

  // ── Validation ────────────────────────────────────────────────────────────────

  @override
  Future<List<BulkRow>> validateRows(List<Map<String, String?>> rawRows) async {
    debugPrint('[CatalogBulk] validateRows: ${rawRows.length} raw rows');
    final client = Supabase.instance.client;
    await _loadCache(client);

    return List.generate(rawRows.length, (i) {
      final row = rawRows[i];
      final rowNum = i + 2;
      debugPrint('[CatalogBulk] Validating row $rowNum — keys: ${row.keys.toList()}');

      final levels = _extractLevels(row);
      debugPrint('[CatalogBulk] Row $rowNum — levels: $levels');

      if (levels.isEmpty) {
        return BulkRow(
          rowNumber: rowNum,
          raw: row,
          status: RowStatus.invalid,
          errors: ['At least level_1 is required'],
          displayLabel: null,
        );
      }

      // Validate is_bookable vs base_price before the duplicate check.
      final isBookable = _parseBool(row['is_bookable'], defaultVal: false);
      if (isBookable) {
        final priceStr = (row['base_price'] ?? '').trim();
        debugPrint('[CatalogBulk] Row $rowNum — is_bookable=true, base_price="$priceStr"');
        if (priceStr.isEmpty || double.tryParse(priceStr) == null) {
          return BulkRow(
            rowNumber: rowNum,
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
        final existingId = _findChild(parentId, name);
        if (idx == levels.length - 1) {
          // Leaf node.
          if (existingId != null) {
            debugPrint('[CatalogBulk] Row $rowNum — duplicate: ${levels.join(' > ')}');
            return BulkRow(
              rowNumber: rowNum,
              raw: row,
              status: RowStatus.skipped,
              skipReason: 'Node "${levels.join(' > ')}" already exists',
              displayLabel: levels.last,
            );
          }
        } else {
          parentId = existingId; // may be null if intermediate is also missing
        }
      }

      debugPrint('[CatalogBulk] Row $rowNum — valid: ${levels.join(' > ')}');
      return BulkRow(
        rowNumber: rowNum,
        raw: row,
        status: RowStatus.valid,
        displayLabel: levels.last,
      );
    });
  }

  // ── Import ────────────────────────────────────────────────────────────────────

  @override
  Future<ImportResult> importRows(List<BulkRow> validRows) async {
    final client = Supabase.instance.client;
    if (_nodesById == null) await _loadCache(client);

    int created = 0;
    final failures = <({int row, String reason})>[];

    for (final br in validRows) {
      try {
        final row = br.raw;
        final levels = _extractLevels(row);

        String? parentId;
        for (var idx = 0; idx < levels.length; idx++) {
          final name = levels[idx];
          final isLeaf = idx == levels.length - 1;

          var nodeId = _findChild(parentId, name);
          if (nodeId == null) {
            // Create the node.
            final slug = await _uniqueSlug(client, name);
            final isBookable = isLeaf &&
                _parseBool(row['is_bookable'], defaultVal: false);
            final isActive = _parseBool(row['is_active'], defaultVal: true);
            final basePrice =
                isLeaf ? double.tryParse(row['base_price'] ?? '') : null;
            final duration =
                isLeaf ? int.tryParse(row['estimated_duration'] ?? '') : null;
            final minOrder = isLeaf
                ? double.tryParse(row['minimum_order_amount'] ?? '')
                : null;
            final description =
                isLeaf ? (row['description'] ?? '').trim() : null;
            final iconKey = isLeaf ? (row['icon_key'] ?? '').trim() : null;
            final sortOrder =
                isLeaf ? (int.tryParse(row['sort_order'] ?? '') ?? 0) : 0;

            final inserted = await client
                .from('catalog_nodes')
                .insert({
                  'name': name,
                  'slug': slug,
                  'is_bookable': isBookable,
                  'is_active': isActive,
                  'sort_order': sortOrder,
                  'base_price': basePrice,
                  'estimated_duration': duration,
                  'minimum_order_amount': minOrder,
                  'description': description != null && description.isNotEmpty ? description : null,
                  'icon_key': iconKey != null && iconKey.isNotEmpty ? iconKey : null,
                })
                .select('id')
                .single();

            nodeId = inserted['id'] as String;

            if (parentId != null) {
              await client.from('catalog_node_relationships').insert({
                'parent_id': parentId,
                'child_id': nodeId,
                'sort_order': sortOrder,
              });
            }

            _addToCache(parentId, nodeId, name);
          }

          parentId = nodeId;
        }

        created++;
      } catch (e) {
        failures.add((row: br.rowNumber, reason: e.toString()));
      }
    }

    return ImportResult(
      created: created,
      skipped: 0,
      failed: failures.length,
      failures: failures,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _extractLevels(Map<String, String?> row) {
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

  Future<String> _uniqueSlug(SupabaseClient client, String name) async {
    final base = name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');

    var candidate = base;
    var suffix = 2;
    while (true) {
      final existing = await client
          .from('catalog_nodes')
          .select('id')
          .eq('slug', candidate);
      if ((existing as List).isEmpty) return candidate;
      candidate = '$base-$suffix';
      suffix++;
    }
  }

  bool _parseBool(String? val, {required bool defaultVal}) {
    if (val == null || val.isEmpty) return defaultVal;
    final v = val.trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    return defaultVal;
  }
}
