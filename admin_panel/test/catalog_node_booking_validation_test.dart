import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/catalog_v2/domain/models/catalog_node.dart';

CatalogNode _node({
  bool isActive = true,
  bool isBookable = true,
  String availabilityStatus = 'active',
  String? unavailabilityMessage,
}) =>
    CatalogNode(
      id: 'svc-1',
      name: 'AC Service',
      slug: 'ac-service',
      sortOrder: 0,
      isActive: isActive,
      isBookable: isBookable,
      availabilityStatus: availabilityStatus,
      unavailabilityMessage: unavailabilityMessage,
      reviewCount: 0,
      childrenCount: 0,
    );

void main() {
  group('CatalogNode.isCurrentlyAvailable', () {
    test('valid bookable service → true', () {
      expect(_node().isCurrentlyAvailable, isTrue);
    });

    test('inactive service → false', () {
      expect(_node(isActive: false).isCurrentlyAvailable, isFalse);
    });

    test('non-bookable service → false', () {
      expect(_node(isBookable: false).isCurrentlyAvailable, isFalse);
    });

    test('availability_status=unavailable → false', () {
      expect(
        _node(availabilityStatus: 'unavailable').isCurrentlyAvailable,
        isFalse,
      );
    });

    test('availability_status=hidden → false', () {
      expect(
        _node(availabilityStatus: 'hidden').isCurrentlyAvailable,
        isFalse,
      );
    });

    test('all flags active but availability=unavailable → false', () {
      expect(
        _node(isActive: true, isBookable: true, availabilityStatus: 'unavailable')
            .isCurrentlyAvailable,
        isFalse,
      );
    });

    test('deleted/non-existent node (inactive + non-bookable) → false', () {
      expect(
        _node(isActive: false, isBookable: false).isCurrentlyAvailable,
        isFalse,
      );
    });
  });

  group('Admin booking validation guard logic', () {
    // Mirrors the repository validation logic for unit-testability.
    String? _validateNode(CatalogNode node) {
      if (!node.isCurrentlyAvailable) {
        final hint = node.unavailabilityMessage;
        return hint?.isNotEmpty == true
            ? hint!
            : 'Service "${node.name}" is currently unavailable';
      }
      return null;
    }

    test('valid service → no error', () {
      expect(_validateNode(_node()), isNull);
    });

    test('inactive service → returns error message', () {
      expect(_validateNode(_node(isActive: false)), isNotNull);
    });

    test('non-bookable service → returns error message', () {
      expect(_validateNode(_node(isBookable: false)), isNotNull);
    });

    test('unavailable service with custom message → uses that message', () {
      expect(
        _validateNode(_node(
          availabilityStatus: 'unavailable',
          unavailabilityMessage: 'Closed for Diwali',
        )),
        'Closed for Diwali',
      );
    });

    test('unavailable service without custom message → generic fallback', () {
      final error = _validateNode(_node(availabilityStatus: 'unavailable'));
      expect(error, contains('AC Service'));
      expect(error, contains('unavailable'));
    });
  });

  group('service_name snapshot logic', () {
    // Mirrors how bookings_repository maps serviceId → service_name.
    Map<String, dynamic> _buildItem({
      required String serviceId,
      String? customName,
      required Map<String, String> nameMap,
    }) {
      return {
        'booking_id': 'bk-1',
        if (serviceId.isNotEmpty) 'service_id': serviceId,
        if (serviceId.isNotEmpty && nameMap.containsKey(serviceId))
          'service_name': nameMap[serviceId],
        if (serviceId.isEmpty && customName != null && customName.isNotEmpty)
          'item_name': customName,
        'quantity': 1,
        'unit_price': 500.0,
        'total_price': 500.0,
      };
    }

    test('catalog item writes service_name from validated map', () {
      final nameMap = {'svc-1': 'AC Service'};
      final item = _buildItem(serviceId: 'svc-1', nameMap: nameMap);
      expect(item['service_name'], 'AC Service');
      expect(item.containsKey('item_name'), isFalse);
    });

    test('custom item writes item_name, no service_id or service_name', () {
      final item = _buildItem(
        serviceId: '',
        customName: 'Special Cleaning',
        nameMap: {},
      );
      expect(item['item_name'], 'Special Cleaning');
      expect(item.containsKey('service_id'), isFalse);
      expect(item.containsKey('service_name'), isFalse);
    });

    test('custom item with blank name writes nothing', () {
      final item = _buildItem(serviceId: '', customName: '', nameMap: {});
      expect(item.containsKey('item_name'), isFalse);
    });
  });
}
