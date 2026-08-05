import 'dart:math';
import '../../../dodo_teams/domain/models/dodo_team.dart';
import '../../../vendor_serving_areas/domain/models/vendor_serving_area.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../../vendors/domain/models/vendor_detail.dart';
import '../../../vendor_tiers/domain/models/vendor_tier.dart';

// ── Unified assignee representation ───────────────────────────────────────────

enum AssigneeKind { vendor, team }

enum AssigneeStatus { available, busy, offline }

class AssigneeCandidate {
  final String id;
  final String name;
  final String? subtitle;
  final double? rating;
  final double? distanceKm; // populated only by legacy Haversine path
  final AssigneeStatus status;
  final AssigneeKind kind;
  final VendorTier? vendorTier;
  // True when the booking is COD and this vendor has no active subscription.
  // Selection is disabled in the assignment dialog; backend enforces the same rule.
  final bool ineligibleForCod;

  const AssigneeCandidate({
    required this.id,
    required this.name,
    this.subtitle,
    this.rating,
    this.distanceKm,
    required this.status,
    required this.kind,
    this.vendorTier,
    this.ineligibleForCod = false,
  });

  factory AssigneeCandidate.fromVendor(
    Vendor v, {
    double? distanceKm,
    bool ineligibleForCod = false,
  }) =>
      AssigneeCandidate(
        id: v.id,
        name: v.businessName,
        subtitle: v.ownerName,
        rating: v.rating,
        distanceKm: distanceKm,
        status: (v.isActive && v.isOnline)
            ? AssigneeStatus.available
            : AssigneeStatus.offline,
        kind: AssigneeKind.vendor,
        vendorTier: v.vendorTier,
        ineligibleForCod: ineligibleForCod,
      );

  factory AssigneeCandidate.fromTeam(DodoTeam t) => AssigneeCandidate(
        id: t.id,
        name: t.teamName,
        subtitle: t.supervisorName,
        rating: null,
        distanceKm: null,
        status: !t.isActive
            ? AssigneeStatus.offline
            : switch (t.status) {
                'Available' => AssigneeStatus.available,
                'Busy' => AssigneeStatus.busy,
                _ => AssigneeStatus.offline,
              },
        kind: AssigneeKind.team,
        vendorTier: null,
      );
}

// ── Legacy type — kept for backwards compat ───────────────────────────────────

class VendorCandidate {
  final Vendor vendor;
  final double distanceKm;
  final double effectiveRadiusKm;

  const VendorCandidate({
    required this.vendor,
    required this.distanceKm,
    required this.effectiveRadiusKm,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class VendorAssignmentService {
  /// Haversine formula — great-circle distance in km between two points.
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

  /// Comparator prioritizing candidates by Vendor Tier Priority (Rank 1 first),
  /// then by Rating (highest first), then by Name (alphabetical).
  static int compareCandidates(AssigneeCandidate a, AssigneeCandidate b) {
    final priorityA = a.vendorTier?.priority ?? 99999;
    final priorityB = b.vendorTier?.priority ?? 99999;
    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }

    final ratingA = a.rating ?? 0.0;
    final ratingB = b.rating ?? 0.0;
    if (ratingA != ratingB) {
      return ratingB.compareTo(ratingA);
    }

    return a.name.compareTo(b.name);
  }

  /// Legacy — unchanged.
  static List<VendorCandidate> rankEligibleVendors({
    required double bookingLat,
    required double bookingLng,
    required List<Vendor> vendors,
    required Map<String, List<VendorServiceArea>> serviceAreasMap,
  }) {
    final candidates = <VendorCandidate>[];
    for (final vendor in vendors) {
      if (!vendor.isActive || !vendor.isOnline) continue;
      if (vendor.latitude == null || vendor.longitude == null) continue;
      final areas = serviceAreasMap[vendor.id] ?? [];
      final radii = areas
          .where((a) => a.radiusKm != null)
          .map((a) => a.radiusKm!)
          .toList();
      if (radii.isEmpty) continue;
      final maxRadius = radii.reduce(max);
      final distance =
          haversineKm(bookingLat, bookingLng, vendor.latitude!, vendor.longitude!);
      if (distance <= maxRadius) {
        candidates.add(VendorCandidate(
          vendor: vendor,
          distanceKm: distance,
          effectiveRadiusKm: maxRadius,
        ));
      }
    }
    // Sort by tier priority first, then distance
    return candidates..sort((a, b) {
      final pA = a.vendor.vendorTier?.priority ?? 99999;
      final pB = b.vendor.vendorTier?.priority ?? 99999;
      if (pA != pB) return pA.compareTo(pB);
      return a.distanceKm.compareTo(b.distanceKm);
    });
  }

  // ── Service-area text matching ─────────────────────────────────────────────

  static bool _serviceAreaMatchesAddress(
      VendorServiceArea sa, String addressLower) {
    final area = sa.area?.trim().toLowerCase();
    return area != null && area.isNotEmpty && addressLower.contains(area);
  }

  /// Returns `({inArea, all})` sorted by Tier Priority -> Rating -> Name.
  static ({List<AssigneeCandidate> inArea, List<AssigneeCandidate> all})
      rankVendorAssignees({
    String? bookingAddress,
    required List<Vendor> vendors,
    required Map<String, List<VendorServiceArea>> serviceAreasMap,
  }) {
    final hasAddress =
        bookingAddress != null && bookingAddress.trim().isNotEmpty;
    final addressLower = hasAddress ? bookingAddress.toLowerCase() : '';

    final inArea = <AssigneeCandidate>[];
    final outside = <AssigneeCandidate>[];

    for (final vendor in vendors) {
      if (!vendor.isActive || !vendor.isOnline) continue;

      if (!hasAddress) {
        outside.add(AssigneeCandidate.fromVendor(vendor));
        continue;
      }

      final areas = serviceAreasMap[vendor.id] ?? [];
      final matches =
          areas.any((sa) => _serviceAreaMatchesAddress(sa, addressLower));

      if (matches) {
        inArea.add(AssigneeCandidate.fromVendor(vendor));
      } else {
        outside.add(AssigneeCandidate.fromVendor(vendor));
      }
    }

    inArea.sort(compareCandidates);
    outside.sort(compareCandidates);

    return (inArea: inArea, all: [...inArea, ...outside]);
  }

  /// Returns `({inArea, all})` using serving-area assignments, sorted by Tier Priority.
  static ({List<AssigneeCandidate> inArea, List<AssigneeCandidate> all})
      rankVendorAssigneesByServingAreas({
    double? bookingLat,
    double? bookingLng,
    required List<Vendor> vendors,
    required List<VendorServingArea> servingAreas,
    required Map<String, Set<String>> assignmentsMap,
    Set<String> busyVendorIds = const {},
    Set<String> codIneligibleVendorIds = const {},
  }) {
    final activeVendors = vendors.where((v) => v.isActive && v.isOnline).toList();

    AssigneeCandidate toCandidate(Vendor v) {
      final ineligible = codIneligibleVendorIds.contains(v.id);
      if (busyVendorIds.contains(v.id)) {
        return AssigneeCandidate(
          id: v.id,
          name: v.businessName,
          subtitle: v.ownerName,
          rating: v.rating,
          distanceKm: null,
          status: AssigneeStatus.busy,
          kind: AssigneeKind.vendor,
          vendorTier: v.vendorTier,
          ineligibleForCod: ineligible,
        );
      }
      return AssigneeCandidate.fromVendor(v, ineligibleForCod: ineligible);
    }

    if (bookingLat == null || bookingLng == null) {
      final all = activeVendors.map(toCandidate).toList()
        ..sort(compareCandidates);
      return (inArea: [], all: all);
    }

    final matchingAreaIds = servingAreas
        .where((area) =>
            haversineKm(bookingLat, bookingLng, area.latitude, area.longitude) <=
            area.radiusKm)
        .map((area) => area.id)
        .toSet();

    final inAreaVendorIds = <String>{};
    for (final areaId in matchingAreaIds) {
      inAreaVendorIds.addAll(assignmentsMap[areaId] ?? {});
    }

    final inArea = <AssigneeCandidate>[];
    final outside = <AssigneeCandidate>[];

    for (final vendor in activeVendors) {
      final candidate = toCandidate(vendor);
      if (inAreaVendorIds.contains(vendor.id)) {
        inArea.add(candidate);
      } else {
        outside.add(candidate);
      }
    }

    inArea.sort(compareCandidates);
    outside.sort(compareCandidates);

    return (inArea: inArea, all: [...inArea, ...outside]);
  }

  /// Returns `({inArea, all})` for DODO team assignment.
  static ({List<AssigneeCandidate> inArea, List<AssigneeCandidate> all})
      rankTeamAssignees({
    String? bookingAddress,
    required List<DodoTeam> teams,
  }) {
    final hasAddress =
        bookingAddress != null && bookingAddress.trim().isNotEmpty;
    final addressLower = hasAddress ? bookingAddress.toLowerCase() : '';

    final inArea = <DodoTeam>[];
    final outside = <DodoTeam>[];

    for (final team in teams) {
      if (!team.isActive) continue;

      if (!hasAddress) {
        outside.add(team);
        continue;
      }

      final locality = team.locality?.trim().toLowerCase() ?? '';
      final matches = locality.isNotEmpty && addressLower.contains(locality);

      if (matches) {
        inArea.add(team);
      } else {
        outside.add(team);
      }
    }

    int priority(DodoTeam t) => switch (t.status) {
          'Available' => 0,
          'Busy' => 1,
          _ => 2,
        };

    inArea.sort((a, b) => priority(a).compareTo(priority(b)));
    outside.sort((a, b) => priority(a).compareTo(priority(b)));

    return (
      inArea: inArea.map(AssigneeCandidate.fromTeam).toList(),
      all: [
        ...inArea.map(AssigneeCandidate.fromTeam),
        ...outside.map(AssigneeCandidate.fromTeam),
      ],
    );
  }
}
