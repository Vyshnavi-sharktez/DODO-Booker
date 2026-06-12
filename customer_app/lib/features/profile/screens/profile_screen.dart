import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../services/profile_providers.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_stats_card.dart';
import '../widgets/profile_menu_tile.dart';
import '../../../routes/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../bookings/modals/my_bookings_modal.dart';
import '../../notifications/widgets/notifications_modal.dart';
import '../../notifications/services/notification_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    // When the user logs in, force a fresh profile fetch.
    ref.listen<bool>(isAuthenticatedProvider, (prev, next) {
      if (next == true) ref.invalidate(profileProvider);
    });

    if (!isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: _UnauthenticatedProfile(
          onSignIn: () async {
            await requireAuth(context, ref);
          },
        ),
      );
    }

    final profileAsync = ref.watch(profileProvider);

    final unreadCount = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: profileAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (e, _) => _ProfileError(onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(profileProvider);
            try { await ref.read(profileProvider.future); } catch (_) {}
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 480 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header ──────────────────────────────────────
                        ProfileHeader(
                          profile: profile,
                          onEditTap: () => context.push(AppRoutes.editProfile),
                        ),

                        const SizedBox(height: 20),

                        // ── Stats ────────────────────────────────────────
                        ProfileStatsCard(profile: profile),

                        // ── Account section ──────────────────────────────
                        ProfileMenuSection(
                          title: 'Account',
                          children: [
                            ProfileMenuTile(
                              icon: Icons.location_on_rounded,
                              iconColor: AppColors.primary,
                              title: 'My Addresses',
                              subtitle: 'Manage saved addresses',
                              onTap: () => context.push(AppRoutes.address),
                            ),
                            ProfileMenuTile(
                              icon: Icons.receipt_long_rounded,
                              iconColor: const Color(0xFF5C6BC0),
                              title: 'My Bookings',
                              subtitle: 'View all your bookings',
                              onTap: () => AppModalDialog.show(
                                context: context,
                                child: const MyBookingsModal(),
                              ).ignore(),
                            ),
                            ProfileMenuTile(
                              icon: Icons.notifications_rounded,
                              iconColor: const Color(0xFFFF6D00),
                              title: 'Notifications',
                              subtitle: 'Alerts and updates',
                              badge: unreadCount > 0 ? '$unreadCount' : null,
                              onTap: () => AppModalDialog.show(
                                context: context,
                                child: const NotificationsModal(),
                              ).ignore(),
                            ),
                            ProfileMenuTile(
                              icon: Icons.favorite_rounded,
                              iconColor: const Color(0xFFE91E63),
                              title: 'Wishlist',
                              subtitle: 'Services you love',
                              onTap: () => context.push(AppRoutes.wishlist),
                            ),
                            ProfileMenuTile(
                              icon: Icons.discount_rounded,
                              iconColor: AppColors.success,
                              title: 'Coupons',
                              subtitle: 'View available offers',
                              onTap: () {},
                            ),
                          ],
                        ),

                        // ── Support section ──────────────────────────────
                        ProfileMenuSection(
                          title: 'Help & Support',
                          children: [
                            ProfileMenuTile(
                              icon: Icons.headset_mic_rounded,
                              iconColor: const Color(0xFF00ACC1),
                              title: 'Support Center',
                              subtitle: '24/7 customer support',
                              onTap: () {},
                            ),
                            ProfileMenuTile(
                              icon: Icons.help_outline_rounded,
                              iconColor: const Color(0xFF7E57C2),
                              title: 'FAQs',
                              subtitle: 'Frequently asked questions',
                              onTap: () {},
                            ),
                            ProfileMenuTile(
                              icon: Icons.info_outline_rounded,
                              iconColor: AppColors.textSecondary,
                              title: 'About Us',
                              subtitle: 'Learn about DODO Booker',
                              onTap: () {},
                            ),
                          ],
                        ),

                        // ── Legal section ────────────────────────────────
                        ProfileMenuSection(
                          title: 'Legal',
                          children: [
                            ProfileMenuTile(
                              icon: Icons.privacy_tip_outlined,
                              iconColor: AppColors.textSecondary,
                              title: 'Privacy Policy',
                              onTap: () {},
                            ),
                            ProfileMenuTile(
                              icon: Icons.description_outlined,
                              iconColor: AppColors.textSecondary,
                              title: 'Terms of Service',
                              onTap: () {},
                            ),
                          ],
                        ),

                        // ── Logout ───────────────────────────────────────
                        const SizedBox(height: 20),
                        _LogoutTile(),

                        // ── App version ──────────────────────────────────
                        const _AppVersion(),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Logout tile ───────────────────────────────────────────────────────────────

class _LogoutTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LogoutTile> createState() => _LogoutTileState();
}

class _LogoutTileState extends ConsumerState<_LogoutTile> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ProfileMenuTile(
        icon: Icons.logout_rounded,
        iconColor: AppColors.error,
        title: 'Logout',
        isDestructive: true,
        onTap: _isLoading ? null : () => _showLogoutDialog(context),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              setState(() => _isLoading = true);
              final router = GoRouter.of(context);
              await ref.read(authServiceProvider).signOut();
              ref.read(authNotifierProvider.notifier).setAuthenticated(false);
              if (!mounted) return;
              setState(() => _isLoading = false);
              router.go(AppRoutes.home);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ── Unauthenticated state ─────────────────────────────────────────────────────

class _UnauthenticatedProfile extends StatelessWidget {
  final VoidCallback onSignIn;
  const _UnauthenticatedProfile({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 38,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sign in to your account',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'View your bookings, manage addresses,\nand access your profile.',
              style: tt.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text(
                'Sign In',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(180, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── App version ───────────────────────────────────────────────────────────────

class _AppVersion extends StatelessWidget {
  const _AppVersion();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Text(
          'DODO Booker v1.0.0',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textHint,
              ),
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header skeleton
        Container(
          height: 240,
          color: AppColors.shimmerBase,
        ),
        const SizedBox(height: 20),
        // Stats skeleton
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 20),
        // Menu skeleton
        ...List.generate(
          5,
          (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ProfileError extends StatelessWidget {
  final VoidCallback onRetry;
  const _ProfileError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            'Could not load profile',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
