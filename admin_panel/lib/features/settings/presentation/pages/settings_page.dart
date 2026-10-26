import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../application/providers/settings_providers.dart';
import '../widgets/settings_section_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  // â”€â”€ Section + field definitions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
          unit: 'â‚¹',
          min: 0,
        ),
        SettingFieldDef(
          key: 'max_booking_amount',
          label: 'Maximum Booking Amount',
          hint: '50000',
          type: SettingFieldType.decimal,
          unit: 'â‚¹',
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
        SettingFieldDef(
          key: 'amc_scheduling_window_days',
          label: 'AMC Scheduling Window',
          hint: 'Days before due date to surface AMC visits in the admin queue',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 1,
          max: 30,
        ),
        SettingFieldDef(
          key: 'default_warranty_days',
          label: 'Default Service Warranty Duration',
          hint: 'Days of active warranty granted upon booking completion',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 1,
          max: 365,
        ),
        SettingFieldDef(
          key: 'default_refund_period_days',
          label: 'Default Refund Eligibility Period',
          hint: 'Days after service completion a customer can request a refund',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 0,
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
        SettingFieldDef(
          key: 'notification_retention_hours',
          label: 'Notification Retention',
          hint: 'Hours to keep notifications before automatic deletion (e.g. 6, 12, 24, 168)',
          type: SettingFieldType.integer,
          unit: 'hrs',
          min: 1,
          max: 8760,
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
        SettingFieldDef(
          key: 'gps_geofence_radius_meters',
          label: 'GPS Geofence Radius',
          hint: 'Maximum allowable distance in meters between vendor GPS logs and service location for geofence validation',
          type: SettingFieldType.integer,
          unit: 'm',
          min: 10,
          max: 10000,
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
    SettingSectionDef(
      id: 'wallet',
      title: 'Wallet Settings',
      description: 'Vendor prepaid wallet enforcement and penalty rules',
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF2C7A7B),
      fields: [
        SettingFieldDef(
          key: 'wallet_minimum_balance',
          label: 'Minimum Wallet Balance',
          hint: '0 = disabled',
          type: SettingFieldType.decimal,
          unit: 'â‚¹',
          min: 0,
        ),
        SettingFieldDef(
          key: 'penalty_vendor_rejection_enabled',
          label: 'Enable Vendor Rejection Penalty',
          hint: 'Charge penalty when a vendor declines/rejects an assigned booking',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'penalty_vendor_rejection_amount',
          label: 'Vendor Rejection Penalty Amount',
          hint: 'Deducted from vendor wallet upon rejection',
          type: SettingFieldType.decimal,
          unit: 'â‚¹',
          min: 0,
        ),
        SettingFieldDef(
          key: 'penalty_vendor_cancellation_enabled',
          label: 'Enable Vendor Cancellation Penalty',
          hint: 'Charge penalty when a vendor cancels an accepted booking',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'penalty_vendor_cancellation_amount',
          label: 'Vendor Cancellation Penalty Amount',
          hint: 'Deducted from vendor wallet upon cancellation',
          type: SettingFieldType.decimal,
          unit: 'â‚¹',
          min: 0,
        ),
        SettingFieldDef(
          key: 'penalty_vendor_noshow_enabled',
          label: 'Enable Vendor No-Show Penalty',
          hint: 'Charge penalty when a vendor no-shows for an assigned booking',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'penalty_vendor_noshow_amount',
          label: 'Vendor No-Show Penalty Amount',
          hint: 'Deducted from vendor wallet upon no-show',
          type: SettingFieldType.decimal,
          unit: 'â‚¹',
          min: 0,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'support_chat',
      title: 'Support Chat Settings',
      description: 'Admin reminders and inactivity auto-close for support conversations',
      icon: Icons.support_agent_rounded,
      color: Color(0xFF0987A0),
      fields: [
        SettingFieldDef(
          key: 'support_reminder_enabled',
          label: 'Admin Reminders',
          hint: 'Periodically remind admins about unanswered customer messages',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'support_reminder_interval_minutes',
          label: 'Reminder Interval',
          hint: 'Minutes between repeat reminder notifications',
          type: SettingFieldType.integer,
          unit: 'min',
          min: 15,
          max: 1440,
        ),
        SettingFieldDef(
          key: 'support_reminder_max_count',
          label: 'Max Reminders per Episode',
          hint: 'Stop reminders after this many per conversation episode',
          type: SettingFieldType.integer,
          min: 1,
          max: 20,
        ),
        SettingFieldDef(
          key: 'support_auto_close_enabled',
          label: 'Auto-Close Inactive Chats',
          hint: 'Automatically close conversations after the idle period elapses',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'support_auto_close_idle_hours',
          label: 'Inactivity Period',
          hint: 'Hours of no messages before a conversation is auto-closed',
          type: SettingFieldType.integer,
          unit: 'hrs',
          min: 1,
          max: 720,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'subscription',
      title: 'Subscription Settings',
      description: 'Control the vendor subscription module and enforcement',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFF6B46C1),
      fields: [
        SettingFieldDef(
          key: 'subscription_enabled',
          label: 'Enable Subscription Module',
          hint: 'Master switch â€” enables subscription plans and enforcement',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'subscription_require_active',
          label: 'Require Active Subscription',
          hint: 'Vendors must have an active subscription to receive bookings',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'subscription_allow_free_vendors',
          label: 'Allow Free Vendors',
          hint: 'Vendors without a subscription can still operate (limited)',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'subscription_auto_disable_cod',
          label: 'Auto Disable COD on Expiry',
          hint: 'Automatically block COD when subscription expires',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'subscription_auto_disable_assignment',
          label: 'Auto Disable Assignment on Expiry',
          hint: 'Block manual booking assignment when subscription expires',
          type: SettingFieldType.toggle,
        ),
        SettingFieldDef(
          key: 'subscription_grace_period_days',
          label: 'Grace Period',
          hint: 'Days after expiry before restrictions apply',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 0,
          max: 30,
        ),
        SettingFieldDef(
          key: 'subscription_reminder_days',
          label: 'Reminder Days Before Expiry',
          hint: 'Send expiry reminder N days in advance',
          type: SettingFieldType.integer,
          unit: 'days',
          min: 1,
          max: 60,
        ),
      ],
    ),
    SettingSectionDef(
      id: 'marketing',
      title: 'Marketing Settings',
      description: 'Abandoned cart detection and campaign configuration',
      icon: Icons.campaign_outlined,
      color: Color(0xFFD69E2E),
      fields: [
        SettingFieldDef(
          key: 'abandoned_cart_inactivity_value',
          label: 'Abandoned Cart Inactivity Duration',
          hint: 'Flag carts inactive for this long as abandoned',
          type: SettingFieldType.integer,
          min: 1,
          max: 720,
        ),
        SettingFieldDef(
          key: 'abandoned_cart_inactivity_unit',
          label: 'Inactivity Unit',
          hint: 'Time unit for the abandoned-cart threshold',
          type: SettingFieldType.dropdown,
          options: ['minutes', 'hours', 'days'],
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

// â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

          Widget sectionGrid;
          if (!twoCol) {
            sectionGrid = Column(
              children: [
                for (final s in sections) ...[
                  SettingsSectionCard(key: ValueKey(s.id), section: s),
                  const SizedBox(height: 20),
                ],
              ],
            );
          } else {
            // Two-column layout: even-index sections on left, odd on right.
            final pairs = sections.asMap().entries;
            final left =
                pairs.where((e) => e.key.isEven).map((e) => e.value).toList();
            final right =
                pairs.where((e) => e.key.isOdd).map((e) => e.value).toList();

            sectionGrid = Row(
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
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ChangePasswordCard(),
              const SizedBox(height: 24),
              sectionGrid,
            ],
          );
        },
      ),
    );
  }
}

// ── Change Password card ──────────────────────────────────────────────────────

class _ChangePasswordCard extends ConsumerStatefulWidget {
  const _ChangePasswordCard();

  @override
  ConsumerState<_ChangePasswordCard> createState() =>
      _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<_ChangePasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _success = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _success = false);
    await ref.read(updatePasswordProvider.notifier).update(_newCtrl.text);
    final asyncState = ref.read(updatePasswordProvider);
    if (asyncState is AsyncData && mounted) {
      setState(() => _success = true);
      _newCtrl.clear();
      _confirmCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(updatePasswordProvider);
    final isLoading = asyncState is AsyncLoading;
    final errorMsg =
        asyncState is AsyncError ? asyncState.error.toString() : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Change Password',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 2),
                    Text('Update your admin panel login password',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 600;
                  final newField = _PasswordField(
                    controller: _newCtrl,
                    label: 'New Password',
                    obscure: _obscureNew,
                    onToggle: () =>
                        setState(() => _obscureNew = !_obscureNew),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 8) return 'Minimum 8 characters';
                      return null;
                    },
                  );
                  final confirmField = _PasswordField(
                    controller: _confirmCtrl,
                    label: 'Confirm Password',
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v != _newCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: newField),
                            const SizedBox(width: 16),
                            Expanded(child: confirmField),
                          ],
                        )
                      else ...[
                        newField,
                        const SizedBox(height: 14),
                        confirmField,
                      ],
                      if (_success) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38A169)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF38A169)
                                    .withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 16, color: Color(0xFF38A169)),
                              SizedBox(width: 8),
                              Text('Password updated successfully',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF38A169),
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                      if (errorMsg != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 16, color: AppColors.error),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(errorMsg,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: isLoading ? null : _submit,
                        icon: isLoading
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                            isLoading ? 'Updating...' : 'Update Password'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

// â”€â”€ Error view â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
