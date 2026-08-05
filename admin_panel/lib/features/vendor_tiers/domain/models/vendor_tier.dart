import 'package:flutter/material.dart';

class VendorTier {
  final String id;
  final String name;
  final String? description;
  final int priority;
  final String badgeColor;
  final String? badgeIcon;
  final bool isActive;
  final int minCompletedBookings;
  final double minRating;
  final double maxCancellationRate;
  final double minCompletionRate;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VendorTier({
    required this.id,
    required this.name,
    this.description,
    required this.priority,
    required this.badgeColor,
    this.badgeIcon,
    required this.isActive,
    this.minCompletedBookings = 0,
    this.minRating = 0.0,
    this.maxCancellationRate = 100.0,
    this.minCompletionRate = 0.0,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  // ── Available Icon Preset Map ──────────────────────────────────────────────
  static const Map<String, IconData> availableIcons = {
    'workspace_premium': Icons.workspace_premium_rounded,
    'star': Icons.star_rounded,
    'military_tech': Icons.military_tech_rounded,
    'verified': Icons.verified_rounded,
    'shield': Icons.shield_rounded,
    'diamond': Icons.diamond_rounded,
    'emoji_events': Icons.emoji_events_rounded,
    'bolt': Icons.bolt_rounded,
    'local_police': Icons.local_police_rounded,
    'auto_awesome': Icons.auto_awesome_rounded,
    'badge': Icons.badge_rounded,
    'verified_user': Icons.verified_user_rounded,
    'grade': Icons.grade_rounded,
    'workspace_premium_outlined': Icons.workspace_premium_outlined,
  };

  // ── UI Helpers ─────────────────────────────────────────────────────────────

  Color get color {
    try {
      final hex = badgeColor.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('0xFF$hex'));
      } else if (hex.length == 8) {
        return Color(int.parse('0x$hex'));
      }
    } catch (_) {}
    return const Color(0xFF4285F4);
  }

  IconData get iconData {
    if (badgeIcon == null || badgeIcon!.isEmpty) {
      return Icons.workspace_premium_rounded;
    }
    return availableIcons[badgeIcon] ?? Icons.workspace_premium_rounded;
  }

  // ── Serialization ──────────────────────────────────────────────────────────

  factory VendorTier.fromMap(Map<String, dynamic> map) => VendorTier(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        description: map['description'] as String?,
        priority: map['priority'] as int? ?? 1,
        badgeColor: map['badge_color'] as String? ?? '#4285F4',
        badgeIcon: map['badge_icon'] as String?,
        isActive: map['is_active'] as bool? ?? true,
        minCompletedBookings: map['min_completed_bookings'] as int? ?? 0,
        minRating: (map['min_rating'] as num?)?.toDouble() ?? 0.0,
        maxCancellationRate: (map['max_cancellation_rate'] as num?)?.toDouble() ?? 100.0,
        minCompletionRate: (map['min_completion_rate'] as num?)?.toDouble() ?? 0.0,
        createdBy: map['created_by'] as String?,
        updatedBy: map['updated_by'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'priority': priority,
        'badge_color': badgeColor,
        'badge_icon': badgeIcon,
        'is_active': isActive,
        'min_completed_bookings': minCompletedBookings,
        'min_rating': minRating,
        'max_cancellation_rate': maxCancellationRate,
        'min_completion_rate': minCompletionRate,
        if (createdBy != null) 'created_by': createdBy,
        if (updatedBy != null) 'updated_by': updatedBy,
      };

  VendorTier copyWith({
    String? id,
    String? name,
    String? description,
    int? priority,
    String? badgeColor,
    String? badgeIcon,
    bool? isActive,
    int? minCompletedBookings,
    double? minRating,
    double? maxCancellationRate,
    double? minCompletionRate,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VendorTier(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        priority: priority ?? this.priority,
        badgeColor: badgeColor ?? this.badgeColor,
        badgeIcon: badgeIcon ?? this.badgeIcon,
        isActive: isActive ?? this.isActive,
        minCompletedBookings: minCompletedBookings ?? this.minCompletedBookings,
        minRating: minRating ?? this.minRating,
        maxCancellationRate: maxCancellationRate ?? this.maxCancellationRate,
        minCompletionRate: minCompletionRate ?? this.minCompletionRate,
        createdBy: createdBy ?? this.createdBy,
        updatedBy: updatedBy ?? this.updatedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
