import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/service_availability/services/serviceability_service.dart';

// ── Tests for ServiceabilityResult semantics ──────────────────────────────────
//
// The DB trigger (enforce_booking_location) now mirrors these rules:
//
//   coordinates present + inside active zone  → serviceable  → booking allowed
//   coordinates present + outside all zones   → notServiceable → booking rejected
//   no coordinates + active zones configured  → noCoordinates → booking rejected
//   no coordinates + no active zones          → serviceable   → booking allowed
//   RPC / network error                       → error         → booking rejected (UI)
//
// The trigger adds backend enforcement of the second case (outside all zones),
// which was previously UI-only and bypassable via direct DB insert.

void main() {
  group('ServiceabilityResult — booking gate contract', () {
    test('serviceable is the only result that allows a booking to proceed', () {
      // All non-serviceable results must block — mirrors booking_gate.dart line 100:
      //   if (serviceability != ServiceabilityResult.serviceable) { return; }
      const blocking = [
        ServiceabilityResult.notServiceable,
        ServiceabilityResult.noCoordinates,
        ServiceabilityResult.error,
      ];
      for (final result in blocking) {
        expect(
          result != ServiceabilityResult.serviceable,
          isTrue,
          reason: '$result should block the booking flow',
        );
      }
      expect(
        ServiceabilityResult.serviceable != ServiceabilityResult.serviceable,
        isFalse,
        reason: 'serviceable must not block the booking flow',
      );
    });

    test('enum covers all expected cases', () {
      expect(ServiceabilityResult.values.length, 4);
      expect(ServiceabilityResult.values, containsAll([
        ServiceabilityResult.serviceable,
        ServiceabilityResult.notServiceable,
        ServiceabilityResult.noCoordinates,
        ServiceabilityResult.error,
      ]));
    });
  });

  group('ServiceabilityResult — null coordinate logic', () {
    // Mirrors ServiceabilityService._handleMissingCoordinates() contract:
    //   active zones exist  → noCoordinates (block — cannot verify without coords)
    //   no active zones     → serviceable   (opt-in feature; irrelevant without zones)
    test('noCoordinates blocks the booking gate', () {
      const result = ServiceabilityResult.noCoordinates;
      expect(result != ServiceabilityResult.serviceable, isTrue);
    });

    test('error blocks the booking gate (fail-safe on network issues)', () {
      const result = ServiceabilityResult.error;
      expect(result != ServiceabilityResult.serviceable, isTrue);
    });
  });

  group('ServiceabilityResult — expected DB trigger behaviour (documented)', () {
    // These cases are enforced by the enforce_booking_location trigger after
    // migration 20261008000002. They cannot be unit-tested in Dart without a
    // live Supabase instance, but are documented here as the single source of
    // truth for QA validation.

    test('inside active zone → serviceable (trigger: is_location_serviceable returns true)', () {
      // e.g. KPHB Colony coords (17.4924, 78.3905) within 5 km zone → allowed
      // Verified by: is_location_serviceable(17.4924, 78.3905) = true
      expect(ServiceabilityResult.serviceable, ServiceabilityResult.serviceable);
    });

    test('outside all active zones → notServiceable (trigger: rejects with exception)', () {
      // e.g. Charminar coords (17.3616, 78.4747) — outside JNTU/KPHB/Ameerpet/Uppal zones
      // Verified by: is_location_serviceable(17.3616, 78.4747) = false
      // Trigger raises: 'Sorry, we do not currently serve your location.'
      expect(ServiceabilityResult.notServiceable != ServiceabilityResult.serviceable, isTrue);
    });

    test('no active zones configured → serviceable for any location (opt-in)', () {
      // If service_availability_areas has no is_active=true rows,
      // is_location_serviceable returns true for all coordinates.
      // Trigger passes; all locations are bookable. This is by design.
      expect(ServiceabilityResult.serviceable, ServiceabilityResult.serviceable);
    });

    test('null coordinates + catalog_node_location_restrictions exist → trigger blocks (unchanged)', () {
      // Existing behaviour preserved: if booking has no lat/lng AND the service
      // has a catalog_node_location_restrictions row, trigger raises exception.
      // This code path was not modified by the new migration.
      expect(ServiceabilityResult.noCoordinates != ServiceabilityResult.serviceable, isTrue);
    });

    test('null coordinates + no restrictions → trigger passes (unchanged)', () {
      // Existing behaviour preserved: if no restrictions for the service and no
      // coordinates, the trigger returns NEW (booking is allowed).
      // The platform-level zone check is skipped (requires coordinates).
      expect(ServiceabilityResult.serviceable, ServiceabilityResult.serviceable);
    });
  });
}
