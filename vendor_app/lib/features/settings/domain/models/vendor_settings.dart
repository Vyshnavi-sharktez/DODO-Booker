class VendorSettings {
  const VendorSettings({
    this.pushNotificationsEnabled = true,
    this.emailNotificationsEnabled = true,
    this.smsNotificationsEnabled = false,
    this.autoAcceptBookings = false,
    this.availabilityStatus = true,
  });

  final bool pushNotificationsEnabled;
  final bool emailNotificationsEnabled;
  final bool smsNotificationsEnabled;
  final bool autoAcceptBookings;
  final bool availabilityStatus;

  VendorSettings copyWith({
    bool? pushNotificationsEnabled,
    bool? emailNotificationsEnabled,
    bool? smsNotificationsEnabled,
    bool? autoAcceptBookings,
    bool? availabilityStatus,
  }) {
    return VendorSettings(
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      emailNotificationsEnabled:
          emailNotificationsEnabled ?? this.emailNotificationsEnabled,
      smsNotificationsEnabled:
          smsNotificationsEnabled ?? this.smsNotificationsEnabled,
      autoAcceptBookings: autoAcceptBookings ?? this.autoAcceptBookings,
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
    );
  }
}
