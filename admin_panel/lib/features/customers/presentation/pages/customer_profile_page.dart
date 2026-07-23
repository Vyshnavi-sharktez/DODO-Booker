import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_back_button.dart';
import '../../application/providers/customer_profile_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/customer_address.dart';
import '../../domain/models/customer_profile.dart';
import '../widgets/customer_edit_dialog.dart';

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');
final _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

const _statusConfig = <String, (String, Color, Color)>{
  'pending': ('Pending', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned': ('Assigned', Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'assigned_to_dodo_team': (
    'DODO Assigned',
    Color(0xFF6B46C1),
    Color(0xFFF3E8FF),
  ),
  'accepted': ('Accepted', Color(0xFF2C7A7B), Color(0xFFE6FFFA)),
  'on_the_way': ('On The Way', Color(0xFF4A6FA5), Color(0xFFEBF4FF)),
  'arrived': ('Arrived', Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'in_progress': ('In Progress', Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed': ('Completed', Color(0xFF38A169), Color(0xFFF0FFF4)),
  'rejected': ('Rejected', Color(0xFFC05621), Color(0xFFFEEBC8)),
  'cancelled': ('Cancelled', Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

// ── Page ──────────────────────────────────────────────────────────────────────

class CustomerProfilePage extends ConsumerWidget {
  const CustomerProfilePage({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(customerProfileProvider(customerId));

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(customerProfileProvider(customerId)),
      ),
      data: (profile) => _ProfileView(profile: profile, customerId: customerId),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load customer profile',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Main profile view ─────────────────────────────────────────────────────────

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.profile, required this.customerId});
  final CustomerProfile profile;
  final String customerId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(profile: profile, customerId: customerId),
            const SizedBox(height: 20),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Booking History'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(profile: profile),
                  _BookingHistoryTab(profile: profile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile header ────────────────────────────────────────────────────────────

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile, required this.customerId});
  final CustomerProfile profile;
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = profile.customer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminBackButton(
          label: 'Customers',
          onTap: () => context.go('/dashboard/customers'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _LargeAvatar(imageUrl: c.profileImageUrl, name: c.fullName),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          c.fullName.isEmpty ? 'Unknown Customer' : c.fullName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ActiveBadge(isActive: c.isActive),
                      if (c.authUserId == null) ...[
                        const SizedBox(width: 6),
                        const _AdminCreatedBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      if (c.phone.isNotEmpty)
                        _InfoChip(Icons.phone_rounded, c.phone),
                      if (c.email.isNotEmpty)
                        _InfoChip(Icons.email_rounded, c.email),
                      _InfoChip(Icons.fingerprint_rounded,
                          'ID: ${c.id.substring(0, 8)}…'),
                      if (c.createdAt != null)
                        _InfoChip(Icons.calendar_today_rounded,
                            'Joined ${_dateFmt.format(c.createdAt!)}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _openEdit(context, ref),
              icon: const Icon(Icons.edit_rounded, size: 14),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openEdit(BuildContext context, WidgetRef ref) {
    final c = profile.customer;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditDialog(
        customer: c,
        onSave: ({
          required fullName,
          required phone,
          required email,
          profileImageUrl,
          required isActive,
        }) async {
          await ref.read(customersNotifierProvider.notifier).updateCustomer(
                c.id,
                fullName: fullName,
                phone: phone,
                email: email,
                profileImageUrl: profileImageUrl,
                isActive: isActive,
              );
          ref.invalidate(customerProfileProvider(customerId));
        },
      ),
    );
  }
}

// ── Overview tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.profile});
  final CustomerProfile profile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: _CustomerInfoCard(customer: profile.customer),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BookingSummaryCards(profile: profile),
                const SizedBox(height: 16),
                _SavedAddressesCard(addresses: profile.addresses),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerInfoCard extends StatelessWidget {
  const _CustomerInfoCard({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return _SectionCard(
      title: 'Customer Information',
      child: Column(
        children: [
          _InfoRow('Full Name', c.fullName.isEmpty ? '—' : c.fullName),
          _InfoRow('Phone', c.phone.isEmpty ? '—' : c.phone),
          _InfoRow('Email', c.email.isEmpty ? '—' : c.email),
          _InfoRow('Status', c.isActive ? 'Active' : 'Inactive'),
          _InfoRow(
            'Account Source',
            c.authUserId != null ? 'Customer App' : 'Admin Created',
          ),
          _InfoRow('Customer ID', c.id),
          if (c.authUserId != null && c.authUserId!.isNotEmpty)
            _InfoRow('Auth User ID', c.authUserId!),
          _InfoRow(
            'Registration Date',
            c.createdAt != null ? _dateTimeFmt.format(c.createdAt!) : '—',
          ),
          _InfoRow(
            'Last Updated',
            c.updatedAt != null ? _dateTimeFmt.format(c.updatedAt!) : '—',
          ),
        ],
      ),
    );
  }
}

class _BookingSummaryCards extends StatelessWidget {
  const _BookingSummaryCards({required this.profile});
  final CustomerProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SmallStatCard(
              label: 'Total Bookings',
              value: '${profile.totalBookings}',
              icon: Icons.receipt_long_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            _SmallStatCard(
              label: 'Completed',
              value: '${profile.completedBookings}',
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _SmallStatCard(
              label: 'Pending',
              value: '${profile.pendingBookings}',
              icon: Icons.hourglass_empty_rounded,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            _SmallStatCard(
              label: 'Cancelled',
              value: '${profile.cancelledBookings}',
              icon: Icons.cancel_rounded,
              color: AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.currency_rupee_rounded,
                    size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currency.format(profile.totalSpent),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Total Amount Spent (Completed)',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (profile.lastBookingDate != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _dateFmt.format(profile.lastBookingDate!),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Last Booking',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedAddressesCard extends StatelessWidget {
  const _SavedAddressesCard({required this.addresses});
  final List<CustomerAddress> addresses;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Saved Addresses',
      trailing: Text(
        '${addresses.length}',
        style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600),
      ),
      child: addresses.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No saved addresses',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          : Column(
              children: addresses.map((a) => _AddressTile(address: a)).toList(),
            ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.address});
  final CustomerAddress address;

  @override
  Widget build(BuildContext context) {
    final isWork = address.addressType.toLowerCase() == 'work';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWork ? Icons.work_rounded : Icons.home_rounded,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      address.addressType,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (address.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Default',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  address.fullAddress.isEmpty ? '—' : address.fullAddress,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Booking history tab ───────────────────────────────────────────────────────

class _BookingHistoryTab extends StatelessWidget {
  const _BookingHistoryTab({required this.profile});
  final CustomerProfile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.bookings.isEmpty) {
      return const _EmptySection(
        icon: Icons.receipt_long_outlined,
        message: 'No booking history',
        sub: "This customer hasn't made any bookings yet.",
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Container(
              color: AppColors.background,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  SizedBox(width: 28),
                  _BHCell('Booking #', flex: 2),
                  _BHCell('Date', flex: 2),
                  _BHCell('Services', flex: 3),
                  _BHCell('Assignee', flex: 2),
                  _BHCell('Status', flex: 2),
                  _BHCell('Amount', flex: 2, align: TextAlign.right),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: profile.bookings.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) =>
                    _ExpandableBookingRow(booking: profile.bookings[i]),
              ),
            ),
            Container(
              color: AppColors.background,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '${profile.bookings.length} booking${profile.bookings.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BHCell extends StatelessWidget {
  const _BHCell(this.label,
      {required this.flex, this.align = TextAlign.left});
  final String label;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ExpandableBookingRow extends StatefulWidget {
  const _ExpandableBookingRow({required this.booking});
  final CustomerBooking booking;

  @override
  State<_ExpandableBookingRow> createState() => _ExpandableBookingRowState();
}

class _ExpandableBookingRowState extends State<_ExpandableBookingRow> {
  bool _expanded = false;

  String _servicesLabel() {
    final items = widget.booking.items;
    if (items.isEmpty) return '—';
    if (items.length == 1) return items.first.serviceName;
    return '${items.first.serviceName} +${items.length - 1} more';
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final cfg = _statusConfig[b.status];
    final statusLabel = cfg?.$1 ?? 'Unknown';
    final statusFg = cfg?.$2 ?? AppColors.textSecondary;
    final statusBg = cfg?.$3 ?? AppColors.border;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    b.bookingNumber?.isNotEmpty == true
                        ? b.bookingNumber!
                        : '#${b.id.substring(0, 8)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    b.serviceDate != null
                        ? _dateFmt.format(b.serviceDate!)
                        : _dateFmt.format(b.createdAt),
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _servicesLabel(),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    b.assigneeName.isEmpty ? '—' : b.assigneeName,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusFg,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _currency.format(b.totalAmount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) _BookingExpandedDetails(booking: b),
      ],
    );
  }
}

class _BookingExpandedDetails extends StatelessWidget {
  const _BookingExpandedDetails({required this.booking});
  final CustomerBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(44, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (b.address != null && b.address!.isNotEmpty) ...[
            _ExpandedDetailRow(
              icon: Icons.location_on_rounded,
              label: 'Address',
              value: b.address!,
            ),
            const SizedBox(height: 8),
          ],
          if (b.items.isNotEmpty) ...[
            Text(
              'SERVICES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            ...b.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.serviceName.isEmpty ? '—' : item.serviceName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (item.categoryName.isNotEmpty)
                              Text(
                                item.subCategoryName.isNotEmpty
                                    ? '${item.categoryName} › ${item.subCategoryName}'
                                    : item.categoryName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${item.quantity} × ${_currency.format(item.unitPrice)}',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 90,
                        child: Text(
                          _currency.format(item.totalPrice),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
          ],
          if (b.discountAmount > 0) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Discount: -${_currency.format(b.discountAmount)}   Total: ${_currency.format(b.totalAmount)}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (b.notes != null && b.notes!.isNotEmpty) ...[
            _ExpandedDetailRow(
              icon: Icons.note_rounded,
              label: 'Notes',
              value: b.notes!,
            ),
            const SizedBox(height: 8),
          ],
          if (b.review != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.star_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  'Review: ${b.review!.rating.toStringAsFixed(1)} ★',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (b.review!.reviewText?.isNotEmpty == true) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '— ${b.review!.reviewText}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandedDetailRow extends StatelessWidget {
  const _ExpandedDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}



// ── Shared small widgets ──────────────────────────────────────────────────────

class _LargeAvatar extends StatelessWidget {
  const _LargeAvatar({this.imageUrl, required this.name});
  final String? imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 36,
        backgroundImage: NetworkImage(imageUrl!),
        backgroundColor: AppColors.border,
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: 36,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.success : AppColors.error,
        ),
      ),
    );
  }
}

class _AdminCreatedBadge extends StatelessWidget {
  const _AdminCreatedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.admin_panel_settings_rounded,
              size: 11, color: AppColors.primary),
          const SizedBox(width: 4),
          const Text(
            'Admin Created',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStatCard extends StatelessWidget {
  const _SmallStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.icon,
    required this.message,
    required this.sub,
  });
  final IconData icon;
  final String message;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
