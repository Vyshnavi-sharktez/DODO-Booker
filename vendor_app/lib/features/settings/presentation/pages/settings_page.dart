import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../auth/presentation/providers/auth_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) context.goNamed(RouteNames.login);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return VendorScaffold(
      title: 'Settings',
      child: ListView(
        children: [
          const SizedBox(height: 8),
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.error),
            title: const Text(
              'Log out',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => _confirmLogout(context, ref),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}


class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
