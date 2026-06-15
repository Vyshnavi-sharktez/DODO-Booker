import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../domain/models/vendor_profile.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_header.dart';
import 'edit_profile_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(vendorProfileProvider);
    final profile = asyncProfile.valueOrNull;

    return VendorScaffold(
      title: 'My Profile',
      actions: [
        if (profile != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditProfilePage(profile: profile),
              ),
            ),
          ),
      ],
      child: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.refresh(vendorProfileProvider),
        ),
        data: (profile) => profile == null
            ? const _EmptyView()
            : _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'Failed to load profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.person_off_outlined,
            size: 64,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            'Vendor profile not found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'No record matched the registered phone number.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile});
  final VendorProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        ProfileHeader(profile: profile),
        const SizedBox(height: 16),
        _InfoSection(
          title: 'Contact',
          items: [
            _InfoItem(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: profile.phone,
            ),
            if (profile.email != null)
              _InfoItem(
                icon: Icons.email_outlined,
                label: 'Email',
                value: profile.email!,
              ),
          ],
        ),
        if (profile.city != null || profile.address != null)
          _InfoSection(
            title: 'Location',
            items: [
              if (profile.city != null)
                _InfoItem(
                  icon: Icons.location_city_outlined,
                  label: 'City',
                  value: profile.city!,
                ),
              if (profile.address != null)
                _InfoItem(
                  icon: Icons.place_outlined,
                  label: 'Address',
                  value: profile.address!,
                ),
            ],
          ),
        _InfoSection(
          title: 'Performance',
          items: [
            _InfoItem(
              icon: Icons.star_outline_rounded,
              label: 'Rating',
              value: profile.rating != null
                  ? '${profile.rating!.toStringAsFixed(1)} / 5.0'
                  : 'Not rated yet',
            ),
            _InfoItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Wallet Balance',
              value: NumberFormat.currency(symbol: '₹', decimalDigits: 2)
                  .format(profile.walletBalance),
            ),
          ],
        ),
        _InfoSection(
          title: 'Account',
          items: [
            _InfoItem(
              icon: Icons.badge_outlined,
              label: 'Account Status',
              value: profile.status[0].toUpperCase() +
                  profile.status.substring(1),
            ),
            _InfoItem(
              icon: profile.isActive
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              label: 'Active',
              value: profile.isActive ? 'Yes' : 'No',
            ),
            if (profile.createdAt != null)
              _InfoItem(
                icon: Icons.calendar_today_outlined,
                label: 'Member Since',
                value: DateFormat('d MMM yyyy').format(profile.createdAt!),
              ),
            if (profile.updatedAt != null)
              _InfoItem(
                icon: Icons.update_outlined,
                label: 'Last Updated',
                value: DateFormat('d MMM yyyy').format(profile.updatedAt!),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Verification',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.primary),
                ),
              ),
              Card(
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('My Documents'),
                  subtitle: const Text('Aadhaar, PAN, GST, Business License'),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => context.push(RoutePaths.documents),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.items});
  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.primary),
            ),
          ),
          Card(
            elevation: 0,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textSecondary),
      ),
      subtitle: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
      ),
      dense: true,
    );
  }
}
