class DashboardBooking {
  const DashboardBooking({
    required this.id,
    required this.bookingNumber,
    this.service,
    required this.status,
    required this.amount,
    this.serviceDate,
    this.createdAt,
  });

  final String id;
  final String bookingNumber;
  final String? service;
  final String status;
  final double amount;
  final DateTime? serviceDate;
  final DateTime? createdAt;
}

class DashboardStats {
  const DashboardStats({
    // Phase 1 — status counts
    required this.assignedCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.rejectedCount,
    required this.todayCount,
    // Phase 1 — lifetime earnings
    required this.totalEarnings,
    // Phase 2 — period earnings
    required this.todayEarnings,
    required this.weeklyEarnings,
    required this.monthlyEarnings,
    // Phase 2 — rates (0–100)
    required this.completionRate,
    required this.rejectionRate,
    // Booking lists
    required this.recentBookings,
    required this.upcomingBookings,
  });

  final int assignedCount;
  final int inProgressCount;
  final int completedCount;
  final int rejectedCount;
  final int todayCount;
  final double totalEarnings;
  final double todayEarnings;
  final double weeklyEarnings;
  final double monthlyEarnings;
  final double completionRate;
  final double rejectionRate;
  final List<DashboardBooking> recentBookings;
  final List<DashboardBooking> upcomingBookings;
}
