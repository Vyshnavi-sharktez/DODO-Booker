import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/booking_item.dart';
import 'package:customer_app/models/my_booking_model.dart';

// ── BookingItem helpers ───────────────────────────────────────────────────────

Map<String, dynamic> _itemJson({
  String? serviceId,
  String? customServiceId,
  String? serviceName,
  String? itemName,
  Map<String, dynamic>? catalogNodes,
  Map<String, dynamic>? vendorServiceRequests,
}) =>
    {
      'service_id': serviceId,
      'custom_service_id': customServiceId,
      'service_name': serviceName,
      'item_name': itemName,
      'quantity': 1,
      'unit_price': 500.0,
      'total_price': 500.0,
      'catalog_nodes': catalogNodes,
      'vendor_service_requests': vendorServiceRequests,
    };

// ── MyBookingModel helper ─────────────────────────────────────────────────────

Map<String, dynamic> _bookingJson({
  required List<Map<String, dynamic>> items,
  String? notes,
}) =>
    {
      'id': 'bk-test-001',
      'customer_id': 'cust-1',
      'service_date': '2026-10-08',
      'status': 'pending',
      'payment_method': 'cash',
      'subtotal': 500.0,
      'discount_amount': 0.0,
      'tax_amount': 0.0,
      'total_amount': 500.0,
      'address': '1 Main St, Hyderabad, Telangana, 500001',
      'notes': notes,
      'created_at': '2026-10-07T10:00:00.000Z',
      'assignment_type': 'Unassigned',
      'booking_items': items,
      'booking_addons': <dynamic>[],
    };

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── BookingItem.fromJson ────────────────────────────────────────────────────

  group('BookingItem.fromJson — service name resolution', () {
    test('a) uses service_name snapshot when present', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'svc-1',
        serviceName: 'AC Service',
      ));
      expect(item.serviceName, 'AC Service');
    });

    test('a) service_name takes priority over catalog_nodes and item_name', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'svc-1',
        serviceName: 'Snapshot Name',
        itemName: 'Admin Name',
        catalogNodes: {'id': 'svc-1', 'name': 'Catalog Name'},
      ));
      expect(item.serviceName, 'Snapshot Name');
    });

    test('b) falls back to catalog_nodes.name when service_name is null', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'cat-1',
        catalogNodes: {'id': 'cat-1', 'name': 'Balcony Cleaning'},
      ));
      expect(item.serviceName, 'Balcony Cleaning');
    });

    test('b) falls back to catalog_nodes.name when service_name is empty', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'cat-1',
        serviceName: '',
        catalogNodes: {'id': 'cat-1', 'name': 'Balcony Cleaning'},
      ));
      expect(item.serviceName, 'Balcony Cleaning');
    });

    test('b) item_name (admin-created) used when service_name is null', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'svc-1',
        itemName: 'Custom Admin Service',
      ));
      expect(item.serviceName, 'Custom Admin Service');
    });

    test('b) item_name preferred over catalog_nodes when service_name is null', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'svc-1',
        itemName: 'Admin Label',
        catalogNodes: {'id': 'svc-1', 'name': 'Catalog Label'},
      ));
      expect(item.serviceName, 'Admin Label');
    });

    test('c) custom service — uses vendor_service_requests.service_name', () {
      final item = BookingItem.fromJson(_itemJson(
        customServiceId: 'vsr-1',
        vendorServiceRequests: {'id': 'vsr-1', 'service_name': 'Deep Cleaning (Custom)'},
      ));
      expect(item.serviceName, 'Deep Cleaning (Custom)');
    });

    test('c) services fallback alias resolves catalog name', () {
      final item = BookingItem.fromJson({
        'service_id': 'svc-legacy',
        'service_name': null,
        'item_name': null,
        'quantity': 1,
        'unit_price': 300.0,
        'total_price': 300.0,
        'services': {'id': 'svc-legacy', 'name': 'Legacy Service'},
        'vendor_service_requests': null,
      });
      expect(item.serviceName, 'Legacy Service');
    });

    test('d) genuinely unavailable — returns empty string at item level', () {
      final item = BookingItem.fromJson(_itemJson(
        serviceId: 'deleted-node',
      ));
      expect(item.serviceName, '');
    });
  });

  // ── MyBookingModel.fromJson — display-level fallback ─────────────────────────

  group('MyBookingModel.fromJson — "Service details unavailable" fallback', () {
    test('a) existing service_name propagates normally', () {
      final json = _bookingJson(items: [
        _itemJson(serviceId: 'svc-1', serviceName: 'AC Repair'),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'AC Repair');
    });

    test('b) service_name recovered via catalog_nodes join', () {
      final json = _bookingJson(items: [
        _itemJson(
          serviceId: 'cat-1',
          catalogNodes: {'id': 'cat-1', 'name': 'Bathroom Cleaning'},
        ),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'Bathroom Cleaning');
    });

    test('b) item_name (admin-created booking) shows correctly', () {
      final json = _bookingJson(items: [
        _itemJson(serviceId: 'svc-1', itemName: 'Pest Control'),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'Pest Control');
    });

    test('c) custom service name from vendor_service_requests shows correctly', () {
      final json = _bookingJson(items: [
        _itemJson(
          customServiceId: 'vsr-1',
          vendorServiceRequests: {'id': 'vsr-1', 'service_name': 'Special Cleaning'},
        ),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'Special Cleaning');
    });

    test('d) single item with no recoverable name → "Service details unavailable"', () {
      final json = _bookingJson(items: [
        _itemJson(serviceId: 'deleted-node'),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'Service details unavailable');
    });

    test('d) no booking_items and no notes → "Service details unavailable"', () {
      final json = _bookingJson(items: []);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'Service details unavailable');
    });

    test('d) no items but notes present → extracts name from notes', () {
      final json = _bookingJson(items: [], notes: 'AC Service - 10:00 AM');
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'AC Service');
    });

    test('d) multiple items with no names → "Service details unavailable"', () {
      final json = _bookingJson(items: [
        _itemJson(serviceId: 'deleted-1'),
        _itemJson(serviceId: 'deleted-2'),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'Service details unavailable');
    });

    test('multi-item booking shows "First + N more" when name available', () {
      final json = _bookingJson(items: [
        _itemJson(serviceId: 'svc-1', serviceName: 'AC Service'),
        _itemJson(serviceId: 'svc-2', serviceName: 'Fan Repair'),
        _itemJson(serviceId: 'svc-3', serviceName: 'Switch Repair'),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, 'AC Service + 2 more');
    });

    test('serviceName is never blank', () {
      final json = _bookingJson(items: [
        _itemJson(serviceId: 'gone'),
      ]);
      final model = MyBookingModel.fromJson(json);
      expect(model.serviceName, isNotEmpty);
    });
  });
}
