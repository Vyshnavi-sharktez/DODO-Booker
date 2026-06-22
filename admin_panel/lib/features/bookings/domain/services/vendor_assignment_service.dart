import 'dart:math';
import '../../../vendors/domain/models/vendor.dart';
import '../../../vendors/domain/models/vendor_detail.dart';

class VendorCandidate {
  final Vendor vendor;
  final double distanceKm;

  /// Maximum radius_km across all service areas declared for this vendor.
  final double effectiveRadiusKm;

  const VendorCandidate({
    required this.vendor,
    required this.distanceKm,
    required this.effectiveRadiusKm,
  });
}

class VendorAssignmentService {
  /// Haversine formula — great-circle distance in km between two points.
  ///
  /// Example:
  ///   haversineKm(17.38500, 78.48670, 17.42100, 78.51200) ≈ 4.56 km
  static double haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  /// Returns eligible vendors sorted nearest-first.
  ///
  /// A vendor is eligible when:
  ///   - `isActive == true`
  ///   - has `latitude` and `longitude` set
  ///   - has at least one `vendor_service_area` row with a non-null `radius_km`
  ///   - `distance(booking, vendor) <= max(radius_km)` across all their areas
  ///
  /// Vendors failing any condition are silently excluded.
  static List<VendorCandidate> rankEligibleVendors({
    required double bookingLat,
    required double bookingLng,
    required List<Vendor> vendors,
    required Map<String, List<VendorServiceArea>> serviceAreasMap,
  }) {
    final candidates = <VendorCandidate>[];

    for (final vendor in vendors) {
      if (!vendor.isActive) continue;
      if (vendor.latitude == null || vendor.longitude == null) continue;

      final areas = serviceAreasMap[vendor.id] ?? [];
      final radii = areas
          .where((a) => a.radiusKm != null)
          .map((a) => a.radiusKm!)
          .toList();
      if (radii.isEmpty) continue;

      final maxRadius = radii.reduce(max);
      final distance = haversineKm(
          bookingLat, bookingLng, vendor.latitude!, vendor.longitude!);

      if (distance <= maxRadius) {
        candidates.add(VendorCandidate(
          vendor: vendor,
          distanceKm: distance,
          effectiveRadiusKm: maxRadius,
        ));
      }
    }

    return candidates..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }
}
