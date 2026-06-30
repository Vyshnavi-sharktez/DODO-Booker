import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/services/profile_providers.dart';

class HomeHeaderSection extends ConsumerWidget {
  const HomeHeaderSection({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuth = ref.watch(isAuthenticatedProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    String? firstName;
    if (isAuth) {
      ref.watch(profileProvider).whenData((p) {
        firstName = p.fullName.trim().split(' ').first;
      });
    }

    final greeting = _greeting();
    final nameDisplay = firstName != null && firstName!.isNotEmpty
        ? firstName!
        : isAuth
            ? 'Welcome back!'
            : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        isDesktop ? 28 : 20,
        isDesktop ? 24 : 16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: TextStyle(
              fontSize: isDesktop ? 14 : 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textHint,
              height: 1.3,
            ),
          ),
          if (nameDisplay != null) ...[
            const SizedBox(height: 2),
            Text(
              nameDisplay,
              style: TextStyle(
                fontSize: isDesktop ? 26 : 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
