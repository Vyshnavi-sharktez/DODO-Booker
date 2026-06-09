import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/settings_providers.dart';
import '../widgets/settings_section_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  // ── Section + field definitions ─────────────────────────────────────────────
  //
  // To add a new setting:
  //   1. Add its key and default to kSettingDefaults (settings_defaults.dart)
  //   2. Add a SettingFieldDef to the appropriate section below
  //   No other changes required.

  static const List<SettingSectionDef> _sections = [
    SettingSectionDef(
      id: 'general',
      title: 'General Settings',
      description: 'Platform identity and contact information',
      icon: Icons.tune_rounded,
      color: AppColors.primary,
      fields: [
        SettingFieldDef(
          key: 'platform_name',
          label: 'Platform Name',
          hint: 'e.g. DODO Booker',
          type: SettingFieldType.text,
        ),
        SettingFieldDef(
          key: 'support_email',
          label: 'Support Email',
          hint: 'support@example.com',
          type: SettingFieldType.email,
        ),
        SettingFieldDef(
          key: 'support_phone',
          label: 'Support Phone',
          hint: '+91 9876543210',
          type: SettingFieldType.phone,
        ),
        SettingFieldDef(
          key: 'default_currency',
          label: 'Default Currency',
          type: SettingFieldType.dropdown,
          options: ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD'],
        ),
        SettingFieldDef(
          key: 'timezone',
          label: 'Timezone',
          type: SettingFieldType.dropdown,
          options: [
            'Asia/Kolkata',
            'UTC',
            'America/New_York',
            'America/Los_Angeles',
            'Europe/London',
            'Europe/Paris',
            'Asia/Dubai',
            'Asia/Singapore',
          ],
        ),
      ],
    ),
    SettingSectionDef(
      id: 'business',
      title: 'Business Settings',
      description: 'Platform commissions, booking limits and automation',
      icon: Icons.business_center_rounded,
      color: Color(0xFF3182CE),
      fields: [
        SettingFieldDef(
          key: 'platform_commission_pct',
          label: 'Platform Commission',
          hint: '10',
          type: SettingFieldType.percent,
          unit: '%',
          min: 0,
          max: 100,
        ),
        SettingFieldDef(
          key: 'min_booking_amount',
          label: 'Minimum Booking Amount',
          hint: '100',
          type: SettingFieldType.decimal,
          unit: '₹',
          min: 0,
        ),
        SettingFieldDef(
          key: 'max_booking_amount',
          label: 'Maximum Booking Amount',
          hint: '50000',
          type: SettingFieldType.decimal,
          unit: '₹',
          min: 0,
        ),
        SettingFieldDef(
          key: 'auto_assign_vendor',
          label: 'Auto Assign Vendor',
          hint: 'Automatically assign the nearest available vendor',
          type: SettingFieldType.toggle,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'booking',
      title: 'Booking Settings',
      description: 'Cancellation, reschedule and advance booking policies',
      icon: Icons.book_online_rounded,
      color: Color(0xFF38A169),
      fields: [
        SettingFieldDef(
          key: 'booking_cancellation_window_hours',
          label: 'Cancellation Window',
          hint: 'Hours before booking that cancellation is allowed',
          type: SettingFieldType.integer,
          unit: 'hrs',
          min: 0,
          max: 720,
        ),
        SettingFieldDef(
          key: 'booking_reschedule_limit',
          label: 'Reschedule Limit',
          hint: 'Maximum reschedules allowed per booking',
          type: SettingFieldType.integer,
          min: 0,
          max: 10,
        ),
        SettingFieldDef(
          key: 'advance_booking_days',
          label: 'Advance Booking Days',
          hint: 'How many days ahead a customer can schedule',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 1,
          max: 365,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'notification',
      title: 'Notification Settings',
      description: 'Control which notification channels are active',
      icon: Icons.notifications_rounded,
      color: Color(0xFF805AD5),
      fields: [
        SettingFieldDef(
          key: 'enable_email_notifications',
          label: 'Email Notifications',
          hint: 'Send booking and status updates via email',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'enable_push_notifications',
          label: 'Push Notifications',
          hint: 'Send in-app push notifications to users',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'enable_sms_notifications',
          label: 'SMS Notifications',
          hint: 'Send booking confirmations via SMS',
          type: SettingFieldType.toggle,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'vendor',
      title: 'Vendor Settings',
      description: 'Onboarding, commissions and settlement rules',
      icon: Icons.store_rounded,
      color: Color(0xFFDD6B20),
      fields: [
        SettingFieldDef(
          key: 'vendor_approval_required',
          label: 'Vendor Approval Required',
          hint: 'New vendors require admin approval before going live',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'vendor_commission_pct',
          label: 'Vendor Commission',
          hint: 'Percentage of booking amount paid to vendor',
          type: SettingFieldType.percent,
          unit: '%',
          min: 0,
          max: 100,
        ),
        SettingFieldDef(
          key: 'settlement_cycle_days',
          label: 'Settlement Cycle',
          hint: 'How often vendor earnings are settled',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 1,
          max: 90,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'customer',
      title: 'Customer Settings',
      description: 'Registration and referral program configuration',
      icon: Icons.people_rounded,
      color: Color(0xFF2B6CB0),
      fields: [
        SettingFieldDef(
          key: 'allow_customer_registration',
          label: 'Allow Customer Registration',
          hint: 'New customers can self-register via the mobile app',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'allow_referral_program',
          label: 'Allow Referral Program',
          hint: 'Enable referral rewards for existing customers',
          type: SettingFieldType.toggle,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () =>
            ref.read(settingsNotifierProvider.notifier).refresh(),
      ),
      data: (_) => _SettingsBody(sections: _sections),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.sections});
  final List<SettingSectionDef> sections;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= 860;
          if (!twoCol) {
            return Column(
              children: [
                for (final s in sections) ...[
                  SettingsSectionCard(key: ValueKey(s.id), section: s),
                  const SizedBox(height: 20),
                ],
              ],
            );
          }

          // Two-column layout: even-index sections on left, odd on right.
          final pairs = sections.asMap().entries;
          final left = pairs
              .where((e) => e.key.isEven)
              .map((e) => e.value)
              .toList();
          final right = pairs
              .where((e) => e.key.isOdd)
              .map((e) => e.value)
              .toList();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    for (final s in left) ...[
                      SettingsSectionCard(key: ValueKey(s.id), section: s),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    for (final s in right) ...[
                      SettingsSectionCard(key: ValueKey(s.id), section: s),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ensure the settings table exists in Supabase.\nRun migration: 20260609000002_create_settings_table.sql',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
