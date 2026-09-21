import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/bulk_upload/data/catalog_row_validator.dart';
import 'package:admin_panel/features/bulk_upload/models/bulk_row.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// Builds an in-memory catalog cache from a list of (parentName, childName) edges.
// Root nodes have no parent (parentName == null).
({
  Map<String?, List<String>> childrenOf,
  Map<String, Map<String, dynamic>> nodesById,
}) _buildCache(List<(String? parent, String child)> edges) {
  final nodesById = <String, Map<String, dynamic>>{};
  final nameToId = <String, String>{};
  var counter = 0;

  String idFor(String name) {
    return nameToId.putIfAbsent(name, () {
      final id = 'n${++counter}';
      nodesById[id] = {'id': id, 'name': name};
      return id;
    });
  }

  final childrenOf = <String?, List<String>>{};
  for (final (parent, child) in edges) {
    final childId = idFor(child);
    if (parent != null) idFor(parent); // ensure parent is in nodesById
    final parentId = parent != null ? nameToId[parent] : null;
    (childrenOf[parentId] ??= []).add(childId);
  }
  return (childrenOf: childrenOf, nodesById: nodesById);
}

Map<String, String?> _row(Map<String, String?> values) => values;

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('extractCatalogLevels', () {
    test('single level_1 only', () {
      expect(extractCatalogLevels({'level_1': 'AC Services'}), ['AC Services']);
    });

    test('two levels', () {
      expect(
        extractCatalogLevels({'level_1': 'AC Services', 'level_2': 'AC Repair'}),
        ['AC Services', 'AC Repair'],
      );
    });

    test('three levels', () {
      expect(
        extractCatalogLevels({
          'level_1': 'Home Cleaning',
          'level_2': 'Deep Cleaning',
          'level_3': 'Kitchen',
        }),
        ['Home Cleaning', 'Deep Cleaning', 'Kitchen'],
      );
    });

    test('stops at first blank level', () {
      expect(
        extractCatalogLevels({
          'level_1': 'AC Services',
          'level_2': '', // blank — stops here
          'level_3': 'Should not appear',
        }),
        ['AC Services'],
      );
    });

    test('null value treated as blank', () {
      expect(
        extractCatalogLevels({'level_1': 'Cat', 'level_2': null}),
        ['Cat'],
      );
    });

    test('missing level_1 returns empty list', () {
      expect(extractCatalogLevels({}), isEmpty);
    });

    test('trims whitespace from level values', () {
      expect(extractCatalogLevels({'level_1': '  AC Services  '}), ['AC Services']);
    });

    test('dynamic levels beyond level_5 are supported', () {
      expect(
        extractCatalogLevels({
          'level_1': 'A',
          'level_2': 'B',
          'level_3': 'C',
          'level_4': 'D',
          'level_5': 'E',
          'level_6': 'F',
        }),
        ['A', 'B', 'C', 'D', 'E', 'F'],
      );
    });
  });

  group('parseCatalogBool', () {
    test('true string → true', () {
      expect(parseCatalogBool('true', defaultVal: false), true);
    });

    test('TRUE (uppercase) → true', () {
      expect(parseCatalogBool('TRUE', defaultVal: false), true);
    });

    test('1 → true', () {
      expect(parseCatalogBool('1', defaultVal: false), true);
    });

    test('yes → true', () {
      expect(parseCatalogBool('yes', defaultVal: false), true);
    });

    test('false string → false', () {
      expect(parseCatalogBool('false', defaultVal: true), false);
    });

    test('FALSE (uppercase) → false', () {
      expect(parseCatalogBool('FALSE', defaultVal: true), false);
    });

    test('0 → false', () {
      expect(parseCatalogBool('0', defaultVal: true), false);
    });

    test('no → false', () {
      expect(parseCatalogBool('no', defaultVal: true), false);
    });

    test('null returns default', () {
      expect(parseCatalogBool(null, defaultVal: true), true);
      expect(parseCatalogBool(null, defaultVal: false), false);
    });

    test('empty string returns default', () {
      expect(parseCatalogBool('', defaultVal: true), true);
    });

    test('unrecognised value returns default', () {
      expect(parseCatalogBool('maybe', defaultVal: false), false);
    });
  });

  group('findCatalogChild', () {
    test('finds a root-level node', () {
      final cache = _buildCache([(null, 'AC Services')]);
      expect(
        findCatalogChild(null, 'AC Services', cache.childrenOf, cache.nodesById),
        isNotNull,
      );
    });

    test('finds a child node case-insensitively', () {
      final cache = _buildCache([(null, 'AC Services'), ('AC Services', 'AC Repair')]);
      final parentId = findCatalogChild(null, 'AC Services', cache.childrenOf, cache.nodesById)!;
      expect(
        findCatalogChild(parentId, 'ac repair', cache.childrenOf, cache.nodesById),
        isNotNull,
      );
    });

    test('returns null when child does not exist', () {
      final cache = _buildCache([(null, 'AC Services')]);
      expect(
        findCatalogChild(null, 'Plumbing', cache.childrenOf, cache.nodesById),
        isNull,
      );
    });

    test('returns null when parent has no children', () {
      final cache = _buildCache([(null, 'AC Services')]);
      final acId = findCatalogChild(null, 'AC Services', cache.childrenOf, cache.nodesById)!;
      expect(
        findCatalogChild(acId, 'AC Repair', cache.childrenOf, cache.nodesById),
        isNull,
      );
    });

    test('empty cache returns null', () {
      expect(findCatalogChild(null, 'Anything', {}, {}), isNull);
    });
  });

  group('validateCatalogRow', () {
    final empty = (childrenOf: <String?, List<String>>{}, nodesById: <String, Map<String, dynamic>>{});

    test('valid new root node', () {
      final result = validateCatalogRow(
        row: _row({'level_1': 'AC Services', 'is_bookable': 'FALSE', 'is_active': 'TRUE'}),
        rowNumber: 2,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.status, RowStatus.valid);
      expect(result.displayLabel, 'AC Services');
    });

    test('valid bookable leaf with base_price', () {
      final cache = _buildCache([(null, 'AC Services')]);
      final result = validateCatalogRow(
        row: _row({
          'level_1': 'AC Services',
          'level_2': 'AC Repair',
          'is_bookable': 'TRUE',
          'base_price': '299',
          'is_active': 'TRUE',
        }),
        rowNumber: 3,
        childrenOf: cache.childrenOf,
        nodesById: cache.nodesById,
      );
      expect(result.status, RowStatus.valid);
      expect(result.displayLabel, 'AC Repair');
    });

    test('invalid — missing level_1', () {
      final result = validateCatalogRow(
        row: _row({'level_1': '', 'is_bookable': 'FALSE'}),
        rowNumber: 2,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.status, RowStatus.invalid);
      expect(result.errors, isNotEmpty);
    });

    test('invalid — is_bookable=TRUE but base_price missing', () {
      final result = validateCatalogRow(
        row: _row({'level_1': 'New Service', 'is_bookable': 'TRUE', 'base_price': ''}),
        rowNumber: 2,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.status, RowStatus.invalid);
      expect(result.errors.first, contains('base_price'));
    });

    test('invalid — is_bookable=TRUE with non-numeric base_price', () {
      final result = validateCatalogRow(
        row: _row({'level_1': 'New Service', 'is_bookable': 'TRUE', 'base_price': 'abc'}),
        rowNumber: 2,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.status, RowStatus.invalid);
    });

    test('skipped — leaf node already exists (duplicate)', () {
      final cache = _buildCache([(null, 'AC Services')]);
      final result = validateCatalogRow(
        row: _row({'level_1': 'AC Services', 'is_bookable': 'FALSE'}),
        rowNumber: 2,
        childrenOf: cache.childrenOf,
        nodesById: cache.nodesById,
      );
      expect(result.status, RowStatus.skipped);
      expect(result.skipReason, contains('already exists'));
    });

    test('skipped — deep duplicate path', () {
      final cache = _buildCache([
        (null, 'Home Cleaning'),
        ('Home Cleaning', 'Deep Cleaning'),
        ('Deep Cleaning', 'Kitchen'),
      ]);
      final result = validateCatalogRow(
        row: _row({
          'level_1': 'Home Cleaning',
          'level_2': 'Deep Cleaning',
          'level_3': 'Kitchen',
          'is_bookable': 'TRUE',
          'base_price': '499',
        }),
        rowNumber: 4,
        childrenOf: cache.childrenOf,
        nodesById: cache.nodesById,
      );
      expect(result.status, RowStatus.skipped);
    });

    test('valid — new child under existing parent', () {
      final cache = _buildCache([(null, 'AC Services')]);
      final result = validateCatalogRow(
        row: _row({
          'level_1': 'AC Services',
          'level_2': 'Brand New Child',
          'is_bookable': 'FALSE',
        }),
        rowNumber: 3,
        childrenOf: cache.childrenOf,
        nodesById: cache.nodesById,
      );
      expect(result.status, RowStatus.valid);
    });

    test('valid — non-bookable node does not require base_price', () {
      final result = validateCatalogRow(
        row: _row({'level_1': 'Plumbing', 'is_bookable': 'FALSE', 'base_price': ''}),
        rowNumber: 2,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.status, RowStatus.valid);
    });

    test('valid — is_bookable absent defaults to non-bookable, no price required', () {
      final result = validateCatalogRow(
        row: _row({'level_1': 'Electrical'}),
        rowNumber: 2,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.status, RowStatus.valid);
    });

    test('duplicate check is case-insensitive', () {
      final cache = _buildCache([(null, 'AC Services')]);
      final result = validateCatalogRow(
        row: _row({'level_1': 'ac services', 'is_bookable': 'FALSE'}),
        rowNumber: 2,
        childrenOf: cache.childrenOf,
        nodesById: cache.nodesById,
      );
      expect(result.status, RowStatus.skipped);
    });

    test('row number is preserved on BulkRow', () {
      final result = validateCatalogRow(
        row: _row({'level_1': 'New Cat'}),
        rowNumber: 42,
        childrenOf: empty.childrenOf,
        nodesById: empty.nodesById,
      );
      expect(result.rowNumber, 42);
    });
  });

  group('BulkRow.copyWith', () {
    test('updates status and errors', () {
      const original = BulkRow(
        rowNumber: 1,
        raw: {'level_1': 'X'},
        status: RowStatus.valid,
      );
      final updated = original.copyWith(
        status: RowStatus.invalid,
        errors: ['Something wrong'],
      );
      expect(updated.status, RowStatus.invalid);
      expect(updated.errors, ['Something wrong']);
      expect(updated.rowNumber, 1); // unchanged
    });
  });
}
