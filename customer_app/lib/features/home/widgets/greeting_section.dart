import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/services/profile_providers.dart';

class GreetingSection extends ConsumerWidget {
  const GreetingSection({super.key});

  static String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isAuth = ref.watch(isAuthenticatedProvider);

    String firstName = '';
    if (isAuth) {
      final fullName =
          ref.watch(profileProvider).whenOrNull(data: (p) => p.fullName) ?? '';
      firstName = fullName.trim().split(' ').first;
    }

    final greeting = firstName.isNotEmpty
        ? '${_timeGreeting()}, $firstName'
        : _timeGreeting();

    final width = MediaQuery.of(context).size.width;
    final fontSize = width < 600 ? 20.0 : (width < 960 ? 24.0 : 28.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        greeting,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
      ),
    );
  }
}
