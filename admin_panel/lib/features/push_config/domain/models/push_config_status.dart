class PushTestTarget {
  final String userId;
  final String displayName;
  final int activeDeviceCount;
  final List<String> platforms;

  const PushTestTarget({
    required this.userId,
    required this.displayName,
    required this.activeDeviceCount,
    required this.platforms,
  });

  factory PushTestTarget.fromMap(Map<String, dynamic> map) {
    final rawPlatforms = map['platforms'];
    final List<String> platforms;
    if (rawPlatforms is List) {
      platforms = rawPlatforms.map((e) => e.toString()).toList();
    } else {
      platforms = [];
    }
    return PushTestTarget(
      userId: map['user_id'] as String,
      displayName: map['display_name'] as String? ?? map['user_id'] as String,
      activeDeviceCount: (map['active_device_count'] as num?)?.toInt() ?? 0,
      platforms: platforms,
    );
  }

  String get platformLabel => platforms.map(_platformDisplay).join(', ');

  static String _platformDisplay(String p) {
    switch (p) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'web':
        return 'Web';
      default:
        return p;
    }
  }
}

class DeviceTokenCount {
  final String userType;
  final String platform;
  final int activeCount;
  final int totalCount;

  const DeviceTokenCount({
    required this.userType,
    required this.platform,
    required this.activeCount,
    required this.totalCount,
  });

  factory DeviceTokenCount.fromMap(Map<String, dynamic> map) {
    return DeviceTokenCount(
      userType: map['user_type'] as String,
      platform: map['platform'] as String,
      activeCount: int.tryParse('${map['active_count'] ?? 0}') ?? 0,
      totalCount: int.tryParse('${map['total_count'] ?? 0}') ?? 0,
    );
  }
}

class PushConfigStatus {
  final bool pushSecretIsSet;
  final bool serviceAccountIsSet;
  final List<DeviceTokenCount> deviceCounts;

  const PushConfigStatus({
    required this.pushSecretIsSet,
    required this.serviceAccountIsSet,
    required this.deviceCounts,
  });

  int activeCountFor(String userType) => deviceCounts
      .where((c) => c.userType == userType)
      .fold(0, (sum, c) => sum + c.activeCount);

  List<DeviceTokenCount> countsFor(String userType) =>
      deviceCounts.where((c) => c.userType == userType).toList();
}
