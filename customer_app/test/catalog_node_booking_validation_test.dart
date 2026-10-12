import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/catalog/models/catalog_node_model.dart';

CatalogNodeModel _node({
  bool isActive = true,
  bool isBookable = true,
  String availabilityStatus = 'active',
  String? unavailabilityMessage,
}) =>
    CatalogNodeModel(
      id: 'svc-1',
      name: 'AC Service',
      slug: 'ac-service',
      sortOrder: 0,
      isActive: isActive,
      isFeatured: false,
      isBookable: isBookable,
      availabilityStatus: availabilityStatus,
      unavailabilityMessage: unavailabilityMessage,
      reviewCount: 0,
    );

void main() {
  group('CatalogNodeModel.isCurrentlyAvailable', () {
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

    test('all flags true but availability=unavailable → false', () {
      expect(
        _node(isActive: true, isBookable: true, availabilityStatus: 'unavailable')
            .isCurrentlyAvailable,
        isFalse,
      );
    });
  });

  group('CatalogNodeModel.unavailabilityReason', () {
    test('inactive → mentions inactive', () {
      expect(
        _node(isActive: false).unavailabilityReason,
        contains('inactive'),
      );
    });

    test('not bookable → mentions not available for booking', () {
      expect(
        _node(isBookable: false).unavailabilityReason,
        contains('not available for booking'),
      );
    });

    test('availability=unavailable with custom message → uses custom message', () {
      expect(
        _node(
          availabilityStatus: 'unavailable',
          unavailabilityMessage: 'We are closed for maintenance',
        ).unavailabilityReason,
        'We are closed for maintenance',
      );
    });

    test('availability=unavailable with no message → generic fallback', () {
      expect(
        _node(availabilityStatus: 'unavailable').unavailabilityReason,
        contains('unavailable'),
      );
    });
  });

  group('CatalogNodeModel booking guard logic', () {
    test('valid service does not throw', () {
      final service = _node();
      expect(
        () {
          if (!service.isCurrentlyAvailable) throw Exception(service.unavailabilityReason);
        },
        returnsNormally,
      );
    });

    test('inactive service throws with reason', () {
      final service = _node(isActive: false);
      expect(
        () {
          if (!service.isCurrentlyAvailable) throw Exception(service.unavailabilityReason);
        },
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('inactive'),
        )),
      );
    });

    test('non-bookable service throws with reason', () {
      final service = _node(isBookable: false);
      expect(
        () {
          if (!service.isCurrentlyAvailable) throw Exception(service.unavailabilityReason);
        },
        throwsA(isA<Exception>()),
      );
    });

    test('unavailable service throws with custom message', () {
      final service = _node(
        availabilityStatus: 'unavailable',
        unavailabilityMessage: 'Service paused for today',
      );
      expect(
        () {
          if (!service.isCurrentlyAvailable) throw Exception(service.unavailabilityReason);
        },
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Service paused for today'),
        )),
      );
    });

    test('deleted/non-existent service (isActive=false, isBookable=false) → throws', () {
      final service = _node(isActive: false, isBookable: false);
      expect(service.isCurrentlyAvailable, isFalse);
      expect(service.unavailabilityReason, isNotEmpty);
    });
  });
}
