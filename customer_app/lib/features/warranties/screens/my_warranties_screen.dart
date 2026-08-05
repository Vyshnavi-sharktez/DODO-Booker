import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/address_model.dart';
import '../../../models/my_booking_model.dart';
import '../models/service_warranty_model.dart';
import '../services/warranty_providers.dart';
import '../../bookings/services/bookings_providers.dart';
import 'warranty_details_screen.dart';

class MyWarrantiesScreen extends ConsumerWidget {
  const MyWarrantiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warrantiesAsync = ref.watch(customerWarrantiesProvider);
    final bookingsAsync = ref.watch(myBookingsProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('My Warranties'),
          elevation: 0,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Claims in Progress'),
              Tab(text: 'Resolved'),
              Tab(text: 'Expired'),
            ],
          ),
        ),
        body: warrantiesAsync.when(
          data: (allWarranties) {
            final activeList = allWarranties.where((w) => w.isActive && !w.isClaimed && !w.isApproved && !w.isResolved && w.reworkBookingId == null).toList();
            final inProgressList = allWarranties.where((w) => w.isClaimed || w.isApproved || w.isReworkAccepted || w.isReworkInProgress).toList();
            final resolvedList = allWarranties.where((w) => w.isResolved).toList();
            final expiredList = allWarranties.where((w) => w.isExpired || w.isRejected).toList();

            final bookingsMap = <String, MyBookingModel>{};
            if (bookingsAsync.valueOrNull != null) {
              for (final b in bookingsAsync.valueOrNull!) {
                bookingsMap[b.id] = b;
              }
            }

            return TabBarView(
              children: [
                _WarrantyTabContent(
                  warranties: activeList,
                  bookingsMap: bookingsMap,
                  emptyTitle: 'No Active Warranties',
                  emptySubtitle: 'Completed service warranties with active coverage will appear here.',
                  emptyIcon: Icons.shield_outlined,
                  onRefresh: () async => ref.invalidate(customerWarrantiesProvider),
                ),
                _WarrantyTabContent(
                  warranties: inProgressList,
                  bookingsMap: bookingsMap,
                  emptyTitle: 'No Active Claims',
                  emptySubtitle: 'Warranty claims undergoing review or rework execution will be tracked here.',
                  emptyIcon: Icons.rate_review_outlined,
                  onRefresh: () async => ref.invalidate(customerWarrantiesProvider),
                ),
                _WarrantyTabContent(
                  warranties: resolvedList,
                  bookingsMap: bookingsMap,
                  emptyTitle: 'No Resolved Claims',
                  emptySubtitle: 'Warranty claims that have been fully serviced and completed will appear here.',
                  emptyIcon: Icons.verified_user_outlined,
                  onRefresh: () async => ref.invalidate(customerWarrantiesProvider),
                ),
                _WarrantyTabContent(
                  warranties: expiredList,
                  bookingsMap: bookingsMap,
                  emptyTitle: 'No Expired Warranties',
                  emptySubtitle: 'Expired warranties or rejected claims will be archived here.',
                  emptyIcon: Icons.history_rounded,
                  onRefresh: () async => ref.invalidate(customerWarrantiesProvider),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load warranties',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    err.toString(),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(customerWarrantiesProvider),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarrantyTabContent extends StatelessWidget {
  final List<ServiceWarrantyModel> warranties;
  final Map<String, MyBookingModel> bookingsMap;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final Future<void> Function() onRefresh;

  const _WarrantyTabContent({
    required this.warranties,
    required this.bookingsMap,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (warranties.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(emptyIcon, size: 48, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  emptyTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  emptySubtitle,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: warranties.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final warranty = warranties[index];
          final booking = bookingsMap[warranty.bookingId] ??
              MyBookingModel(
                id: warranty.bookingId,
                bookingNumber: warranty.bookingNumber,
                serviceId: 'service_1',
                serviceName: 'Service',
                items: const [],
                addons: const [],
                address: const AddressModel(
                  id: '',
                  label: 'Service Address',
                  line1: '',
                  city: '',
                  state: '',
                  pincode: '',
                ),
                scheduledDate: warranty.issuedAt,
                timeSlot: '10:00 AM',
                baseAmount: 0.0,
                taxAmount: 0.0,
                totalAmount: 0.0,
                status: 'completed',
                assignmentType: 'External Vendor',
                createdAt: warranty.issuedAt,
                vendorName: warranty.vendorName,
                timeline: const [],
              );

          return _CustomerWarrantyCardItem(
            warranty: warranty,
            booking: booking,
          );
        },
      ),
    );
  }
}

class _CustomerWarrantyCardItem extends StatelessWidget {
  final ServiceWarrantyModel warranty;
  final MyBookingModel booking;

  const _CustomerWarrantyCardItem({
    required this.warranty,
    required this.booking,
  });

  Color _getStatusColor(String statusStr) {
    switch (statusStr.toLowerCase()) {
      case 'active':
        return const Color(0xFF38A169);
      case 'under review':
        return const Color(0xFF805AD5);
      case 'approved':
      case 'vendor accepted':
        return const Color(0xFF3182CE);
      case 'in progress':
        return const Color(0xFFD69E2E);
      case 'rework completed':
      case 'resolved':
        return const Color(0xFF2B6CB0);
      case 'rejected':
        return const Color(0xFFE53E3E);
      case 'expired':
      default:
        return const Color(0xFF718096);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final statusColor = _getStatusColor(warranty.effectiveStatus);
    final bookingNum = warranty.bookingNumber ?? (booking.displayBookingNumber);
    final serviceName = booking.serviceName.isNotEmpty && booking.serviceName != 'Service'
        ? booking.serviceName
        : 'Service #$bookingNum';

    final vendorName = warranty.reworkVendorName ?? warranty.vendorName ?? booking.vendorName ?? 'DODO Authorized Vendor';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WarrantyDetailsScreen(
                  booking: booking,
                  warranty: warranty,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Certificate Code & Status Chip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            warranty.isActive ? Icons.verified_user_rounded : Icons.shield_rounded,
                            size: 16,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          warranty.certificateNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        warranty.effectiveStatus.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Service Name & Booking Ref
                Text(
                  serviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.receipt_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Booking #$bookingNum',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (warranty.reworkBookingNumber != null) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.build_outlined, size: 14, color: Color(0xFF38A169)),
                      const SizedBox(width: 4),
                      Text(
                        'Rework #${warranty.reworkBookingNumber}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF38A169)),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(Icons.store_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        vendorName,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const Divider(height: 20),

                // Footer Date & Action Arrow
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_outlined, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          warranty.isResolved
                              ? 'Resolved on ${dateFmt.format(warranty.reworkCompletedAt ?? warranty.updatedAt)}'
                              : (warranty.isClaimed || warranty.isApproved || warranty.isReworkInProgress
                                  ? 'Claimed on ${dateFmt.format(warranty.claimedAt!)}'
                                  : (warranty.isActive
                                      ? 'Expires on ${dateFmt.format(warranty.expiresAt)}'
                                      : 'Expired on ${dateFmt.format(warranty.expiresAt)}')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: warranty.isActive ? const Color(0xFF276749) : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Row(
                      children: [
                        Text(
                          'View Details',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
