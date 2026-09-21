import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../bulk_upload_module.dart';
import '../../models/bulk_row.dart';
import '../catalog_row_validator.dart';
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
      final result = validateCatalogRow(
        row: row,
        rowNumber: rowNum,
        childrenOf: _childrenOf!,
        nodesById: _nodesById!,
      );
      debugPrint('[CatalogBulk] Row $rowNum — ${result.status.name}: ${result.displayLabel}');
      return result;
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
        final levels = extractCatalogLevels(row);

        String? parentId;
        for (var idx = 0; idx < levels.length; idx++) {
          final name = levels[idx];
          final isLeaf = idx == levels.length - 1;

          var nodeId = findCatalogChild(parentId, name, _childrenOf!, _nodesById!);
          if (nodeId == null) {
            // Create the node.
            final slug = await _uniqueSlug(client, name);
            final isBookable = isLeaf &&
                parseCatalogBool(row['is_bookable'], defaultVal: false);
            final isActive = parseCatalogBool(row['is_active'], defaultVal: true);
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

}
