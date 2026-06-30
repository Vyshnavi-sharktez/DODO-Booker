import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../models/profile_model.dart';
import '../services/profile_providers.dart';
import '../widgets/profile_menu_tile.dart';
import '../../../routes/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../address/screens/address_screen.dart';
import '../../wishlist/screens/wishlist_screen.dart';
import 'settings_screen.dart';
import 'package:customer_app/features/bookings/modals/my_bookings_modal.dart';
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    ref.listen<bool>(isAuthenticatedProvider, (prev, next) {
      if (next == true) ref.invalidate(profileProvider);
    });

    if (!isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.surfaceVariant,
        appBar: AppBar(title: const Text('My Account')),
        body: _UnauthenticatedProfile(
          onSignIn: () async => requireAuth(context, ref),
        ),
      );
    }

    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(title: const Text('My Account')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: profileAsync.when(
            loading: () => const _ProfileSkeleton(),
            error: (e, _) =>
                _ProfileError(onRetry: () => ref.invalidate(profileProvider)),
            data: (profile) => _ProfileBody(profile: profile),
          ),
        ),
      ),
    );
  }
}

// ── Authenticated body ─────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  final ProfileModel profile;
  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      displacement: 20,
      onRefresh: () async {
        ref.invalidate(profileProvider);
        try {
          await ref.read(profileProvider.future);
        } catch (_) {}
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // ── Profile card ──────────────────────────────────────────
              _ProfileCard(profile: profile),

              // ── Account section ───────────────────────────────────────
              const _SectionLabel('Account'),

              _FloatingCard(
                child: ProfileMenuTile(
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.primary,
                  title: 'Saved Addresses',
                  subtitle: 'Manage your delivery locations',
                  onTap: () => _openResponsive(
                    context,
                    desktopModal: () => PageSheet.show(
                      context,
                      title: 'My Addresses',
                      child: const AddressScreen(inModal: true),
                    ),
                    mobileRoute: () => context.push(AppRoutes.address),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _FloatingCard(
                child: ProfileMenuTile(
                  icon: Icons.favorite_rounded,
                  iconColor: const Color(0xFFE91E63),
                  title: 'Wishlist',
                  subtitle: 'Services you have saved',
                  onTap: () => _openResponsive(
                    context,
                    desktopModal: () => PageSheet.show(
                      context,
                      title: 'Wishlist',
                      child: const WishlistScreen(inModal: true),
                    ),
                    mobileRoute: () => context.push(AppRoutes.wishlist),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _FloatingCard(
                child: ProfileMenuTile(
                  icon: Icons.receipt_long_rounded,
                  iconColor: Colors.blue,
                  title: 'My Bookings',
                  subtitle: 'View and manage your bookings',
                  onTap: () => _openResponsive(
                    context,
                    desktopModal: () => PageSheet.show(
                      context,
                      title: 'My Bookings',
                      child: const MyBookingsModal(),
                    ),
                    mobileRoute: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyBookingsModal(),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Preferences section ───────────────────────────────────
              const _SectionLabel('Preferences'),
              
              _FloatingCard(
                child: ProfileMenuTile(
                  icon: Icons.settings_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'Settings',
                  subtitle: 'App preferences',
                  onTap: () => _openResponsive(
                    context,
                    desktopModal: () => PageSheet.show(
                      context,
                      title: 'Settings',
                      child: const SettingsScreen(inModal: true),
                    ),
                    mobileRoute: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static void _openResponsive(
    BuildContext context, {
    required VoidCallback desktopModal,
    required VoidCallback mobileRoute,
  }) {
    if (MediaQuery.of(context).size.width >= 768) {
      desktopModal();
    } else {
      mobileRoute();
    }
  }
}

// ── Floating card wrapper ──────────────────────────────────────────────────────

class _FloatingCard extends StatelessWidget {
  final Widget child;
  const _FloatingCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textHint,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Profile card (hero) ────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final ProfileModel profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          children: [
            _AvatarWidget(profile: profile),

            const SizedBox(height: 16),

            Text(
              profile.fullName.isEmpty ? 'Set your name' : profile.fullName,
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 6),

            if (profile.email != null && profile.email!.isNotEmpty) ...[
              Text(
                profile.email!,
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
            ],

            if (profile.mobileNumber.isNotEmpty)
              Text(
                profile.mobileNumber,
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),

            const SizedBox(height: 24),

            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.editProfile),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border, width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 11,
                ),
                minimumSize: Size.zero,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar ─────────────────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final ProfileModel profile;
  const _AvatarWidget({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.textPrimary,
        border: Border.all(color: AppColors.gold.withAlpha(180), width: 2.5),
      ),
      child: profile.imageUrl != null
          ? ClipOval(
              child: Image.network(
                profile.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (ctx, e, st) => _Initials(profile.initials),
              ),
            )
          : _Initials(profile.initials),
    );
  }
}

class _Initials extends StatelessWidget {
  final String text;
  const _Initials(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Unauthenticated state ──────────────────────────────────────────────────────

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
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0C000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 40,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sign in to your account',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Access your bookings, addresses,\nwishlist and more.',
              style: tt.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text(
                'Sign In',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(180, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  Widget _shimmer({double w = double.infinity, double h = 14, double r = 8}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(r),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),

          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Column(
              children: [
                _shimmer(w: 96, h: 96, r: 48),
                const SizedBox(height: 16),
                _shimmer(w: 130, h: 18, r: 6),
                const SizedBox(height: 10),
                _shimmer(w: 160, h: 13),
                const SizedBox(height: 6),
                _shimmer(w: 110, h: 13),
                const SizedBox(height: 24),
                _shimmer(w: 120, h: 38, r: 24),
              ],
            ),
          ),

          ...List.generate(
            4,
            (i) => Padding(
              padding: EdgeInsets.fromLTRB(16, i == 0 ? 32 : 12, 16, 0),
              child: _shimmer(h: 56, r: 16),
            ),
          ),

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _shimmer(h: 56, r: 16),
          ),
        ],
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────

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
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
