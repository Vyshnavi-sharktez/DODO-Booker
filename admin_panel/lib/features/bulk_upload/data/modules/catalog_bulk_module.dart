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
  If a node with the exact path already exists AND all fields match, the row is SKIPPED.
  If the path exists but any field differs, the existing record is UPDATED.
  Duplicate rows within the uploaded file are SKIPPED after the first occurrence.

Notes:
  - Column headers in row 1 must not be changed.
  - Dynamic levels: you may extend to level_6, level_7, etc. by adding more columns.
  - Keep this file as .xlsx format.''';

  @override
  List<Map<String, String?>> parseXlsx(Uint8List bytes) => xu.parseXlsx(bytes);

  // ── Cache management ──────────────────────────────────────────────────────────

  Future<void> _loadCache(SupabaseClient client) async {
    debugPrint('[CatalogBulk] _loadCache: querying catalog_nodes + relationships');
    final nodes = await client.from('catalog_nodes').select(
      'id, name, is_bookable, is_active, base_price, estimated_duration, '
      'minimum_order_amount, description, icon_key, sort_order',
    );
    final rels = await client.from('catalog_node_relationships').select('parent_id, child_id');
    debugPrint('[CatalogBulk] _loadCache: ${(nodes as List).length} nodes, ${(rels as List).length} rels');

    final nodesById = <String, Map<String, dynamic>>{};
    for (final n in nodes as List) {
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
    if (nm == null || cm == null) return;
    nm[nodeId] = {'id': nodeId, 'name': name};
    (cm[parentId] ??= []).add(nodeId);
  }

  // ── Validation ────────────────────────────────────────────────────────────────

  @override
  Future<List<BulkRow>> validateRows(List<Map<String, String?>> rawRows) async {
    debugPrint('[CatalogBulk] validateRows: ${rawRows.length} raw rows');
    final client = Supabase.instance.client;
    await _loadCache(client);

    final seenPaths = <String>{};

    return List.generate(rawRows.length, (i) {
      final row = rawRows[i];
      final rowNum = i + 2;
      debugPrint('[CatalogBulk] Validating row $rowNum — keys: ${row.keys.toList()}');
      final result = validateCatalogRow(
        row: row,
        rowNumber: rowNum,
        childrenOf: _childrenOf!,
        nodesById: _nodesById!,
        seenPaths: seenPaths,
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
    int updated = 0;
    final failures = <({int row, String reason})>[];

    for (final br in validRows) {
      try {
        final row = br.raw;
        final levels = extractCatalogLevels(row);
        final isLeafBookable = parseCatalogBool(row['is_bookable'], defaultVal: false);
        final isLeafActive = parseCatalogBool(row['is_active'], defaultVal: true);
        final leafBasePrice = double.tryParse(row['base_price'] ?? '');
        final leafDuration = int.tryParse(row['estimated_duration'] ?? '');
        final leafMinOrder = double.tryParse(row['minimum_order_amount'] ?? '');
        final leafDescription = (row['description'] ?? '').trim();
        final leafIconKey = (row['icon_key'] ?? '').trim();
        final leafSortOrder = int.tryParse(row['sort_order'] ?? '') ?? 0;

        if (br.status == RowStatus.updatePending) {
          // Leaf exists — update fields in place.
          await client.from('catalog_nodes').update({
            'is_bookable': isLeafBookable,
            'is_active': isLeafActive,
            'base_price': leafBasePrice,
            'estimated_duration': leafDuration,
            'minimum_order_amount': leafMinOrder,
            'description': leafDescription.isNotEmpty ? leafDescription : null,
            'icon_key': leafIconKey.isNotEmpty ? leafIconKey : null,
            'sort_order': leafSortOrder,
          }).eq('id', br.existingId!);
          updated++;
          continue;
        }

        // valid: walk path and create any missing nodes.
        String? parentId;
        for (var idx = 0; idx < levels.length; idx++) {
          final name = levels[idx];
          final isLeaf = idx == levels.length - 1;

          var nodeId = findCatalogChild(parentId, name, _childrenOf!, _nodesById!);
          if (nodeId == null) {
            final slug = await _uniqueSlug(client, name);
            final inserted = await client
                .from('catalog_nodes')
                .insert({
                  'name': name,
                  'slug': slug,
                  'is_bookable': isLeaf ? isLeafBookable : false,
                  'is_active': isLeaf ? isLeafActive : true,
                  'sort_order': isLeaf ? leafSortOrder : 0,
                  'base_price': isLeaf ? leafBasePrice : null,
                  'estimated_duration': isLeaf ? leafDuration : null,
                  'minimum_order_amount': isLeaf ? leafMinOrder : null,
                  'description': isLeaf && leafDescription.isNotEmpty ? leafDescription : null,
                  'icon_key': isLeaf && leafIconKey.isNotEmpty ? leafIconKey : null,
                })
                .select('id')
                .single();

            nodeId = inserted['id'] as String;

            if (parentId != null) {
              await client.from('catalog_node_relationships').insert({
                'parent_id': parentId,
                'child_id': nodeId,
                'sort_order': isLeaf ? leafSortOrder : 0,
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
      updated: updated,
      skipped: 0,
      failed: failures.length,
      failures: failures,
    );
  }

  // ── Export ────────────────────────────────────────────────────────────────────

  @override
  bool get supportsExport => true;

  @override
  Future<Uint8List> exportCurrentData() async {
    final client = Supabase.instance.client;

    final nodesRaw = await client.from('catalog_nodes').select(
      'id, name, is_bookable, base_price, estimated_duration, '
      'minimum_order_amount, description, icon_key, sort_order, is_active',
    );
    final relsRaw = await client
        .from('catalog_node_relationships')
        .select('parent_id, child_id');

    final nodesById = <String, Map<String, dynamic>>{};
    for (final n in nodesRaw as List) {
      final id = n['id'] as String?;
      if (id == null) continue;
      nodesById[id] = Map<String, dynamic>.from(n as Map);
    }

    final allChildIds = <String>{};
    final childrenOf = <String, List<String>>{};
    for (final r in relsRaw as List) {
      final parentId = r['parent_id'] as String?;
      final childId = r['child_id'] as String?;
      if (childId == null) continue;
      allChildIds.add(childId);
      if (parentId != null) (childrenOf[parentId] ??= []).add(childId);
    }

    final rootIds =
        nodesById.keys.where((id) => !allChildIds.contains(id)).toList();

    var maxDepth = 1;
    final rawRows = <({List<String> path, List<String> attrs})>[];

    void dfs(String nodeId, List<String> parentPath) {
      final n = nodesById[nodeId];
      if (n == null) return;
      final path = [...parentPath, (n['name'] as String?) ?? ''];
      if (path.length > maxDepth) maxDepth = path.length;

      rawRows.add((
        path: path,
        attrs: [
          ((n['is_bookable'] as bool?) ?? false) ? 'TRUE' : 'FALSE',
          _numStr(n['base_price']),
          _numStr(n['estimated_duration']),
          _numStr(n['minimum_order_amount']),
          (n['description'] as String?) ?? '',
          (n['icon_key'] as String?) ?? '',
          _numStr(n['sort_order']),
          ((n['is_active'] as bool?) ?? true) ? 'TRUE' : 'FALSE',
        ],
      ));

      for (final childId in (childrenOf[nodeId] ?? [])) {
        dfs(childId, path);
      }
    }

    for (final rootId in rootIds) {
      dfs(rootId, []);
    }

    final numLevels = maxDepth < 5 ? 5 : maxDepth;
    final columns = [
      for (var i = 1; i <= numLevels; i++) 'level_$i',
      'is_bookable',
      'base_price',
      'estimated_duration',
      'minimum_order_amount',
      'description',
      'icon_key',
      'sort_order',
      'is_active',
    ];

    final dataRows = rawRows.map((r) {
      final path = List<String>.from(r.path);
      while (path.length < numLevels) path.add('');
      return [...path, ...r.attrs];
    }).toList();

    return xu.generateExport(
      columns: columns,
      dataRows: dataRows,
      sheetName: 'Catalog',
    );
  }

  static String _numStr(dynamic v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v is double) {
      return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
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
