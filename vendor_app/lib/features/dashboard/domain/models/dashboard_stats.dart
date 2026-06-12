class DashboardStats {
  const DashboardStats({
    this.totalBookings = 0,
    this.pendingBookings = 0,
    this.completedBookings = 0,
    this.todayEarnings = 0.0,
    this.monthEarnings = 0.0,
    this.walletBalance = 0.0,
    this.averageRating = 0.0,
    this.totalReviews = 0,
  });

  final int totalBookings;
  final int pendingBookings;
  final int completedBookings;
  final double todayEarnings;
  final double monthEarnings;
  final double walletBalance;
  final double averageRating;
  final int totalReviews;
}
