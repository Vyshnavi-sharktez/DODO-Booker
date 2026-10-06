import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../../../features/payment_config/presentation/widgets/secret_field_widget.dart';
import '../../../../features/settings/application/providers/settings_providers.dart';
import '../../application/providers/push_config_providers.dart';
import '../../domain/models/push_config_status.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

class PushConfigPage extends ConsumerWidget {
  const PushConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(pushConfigNotifierProvider);

    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => ref.read(pushConfigNotifierProvider.notifier).refresh(),
      ),
      data: (_) => const _PushConfigBody(),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _PushConfigBody extends ConsumerStatefulWidget {
  const _PushConfigBody();

  @override
  ConsumerState<_PushConfigBody> createState() => _PushConfigBodyState();
}

class _PushConfigBodyState extends ConsumerState<_PushConfigBody> {
  bool _enabledToggle = true;
  bool _dirty = false;
  bool _saving = false;

  // Per-secret status notifiers, updated optimistically after successful saves.
  final _pushSecretStatus = ValueNotifier<bool>(false);
  final _serviceAccountStatus = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFromSettings();
      _initSecretStatuses();
    });
  }

  @override
  void dispose() {
    _pushSecretStatus.dispose();
    _serviceAccountStatus.dispose();
    super.dispose();
  }

  void _initFromSettings() {
    if (!mounted || _dirty) return;
    final settings = ref.read(settingsNotifierProvider).valueOrNull ?? {};
    final enabled =
        SettingsNotifier.effectiveValue(
            settings, 'enable_push_notifications') ==
        'true';
    setState(() => _enabledToggle = enabled);
  }

  void _initSecretStatuses() {
    if (!mounted) return;
    final status = ref.read(pushConfigNotifierProvider).valueOrNull;
    if (status != null) {
      _pushSecretStatus.value = status.pushSecretIsSet;
      _serviceAccountStatus.value = status.serviceAccountIsSet;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsNotifierProvider.notifier).saveSection({
        'enable_push_notifications': _enabledToggle ? 'true' : 'false',
      });
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push notification setting saved'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
      }
    }
  }

  Future<void> _sendTestNotification() async {
    final status = ref.read(pushConfigNotifierProvider).valueOrNull;
    if (status == null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SendTestDialog(status: status),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, String>>>(
      settingsNotifierProvider,
      (_, next) => next.whenOrNull(data: (_) => _initFromSettings()),
    );
    ref.listen<AsyncValue<PushConfigStatus>>(
      pushConfigNotifierProvider,
      (_, next) => next.whenOrNull(data: (s) {
        if (mounted) {
          _pushSecretStatus.value = s.pushSecretIsSet;
          _serviceAccountStatus.value = s.serviceAccountIsSet;
        }
      }),
    );

    final status =
        ref.watch(pushConfigNotifierProvider).valueOrNull ??
        const PushConfigStatus(
          pushSecretIsSet: false,
          serviceAccountIsSet: false,
          deviceCounts: [],
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 860;
              if (!twoCol) {
                return Column(
                  children: [
                    _buildConfigCard(),
                    const SizedBox(height: 20),
                    _buildDevicesCard(status),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildConfigCard()),
                  const SizedBox(width: 20),
                  Expanded(child: _buildDevicesCard(status)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Page header ──────────────────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.notifications_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Push Notification Configuration',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'FCM credentials, delivery status, and registered devices',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Push Function Secret and Firebase Service Account are write-only. '
                  'Values are encrypted server-side via Supabase Vault and are never shown after saving.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── FCM Configuration Card ───────────────────────────────────────────────────

  Widget _buildConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildConfigCardHeader(),
          _buildConfigCardBody(),
          _buildConfigCardActions(),
        ],
      ),
    );
  }

  Widget _buildConfigCardHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6D00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: Color(0xFFFF6D00),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Firebase Cloud Messaging',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Text(
                  'Server-side push delivery to all apps',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_dirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Unsaved',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfigCardBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToggle(
            label: 'Enable Push Notifications',
            hint: 'Send push notifications to customers, vendors and admins',
            value: _enabledToggle,
            onChanged: (v) => setState(() {
              _enabledToggle = v;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.border),
          const SizedBox(height: 4),
          const Text(
            'Secrets — write-only. Values are encrypted server-side and are never displayed after saving.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<bool>(
            valueListenable: _pushSecretStatus,
            builder: (_, isSet, _) => SecretFieldWidget(
              label: 'Push Function Secret',
              hint:
                  'Bearer token matching the PUSH_FUNCTION_SECRET edge function env var',
              isConfigured: isSet,
              onSave: (value) async {
                await ref
                    .read(pushConfigNotifierProvider.notifier)
                    .upsertFcmVaultSecret('push_function_secret', value);
                _pushSecretStatus.value = true;
              },
            ),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<bool>(
            valueListenable: _serviceAccountStatus,
            builder: (_, isSet, _) => SecretFieldWidget(
              label: 'Firebase Service Account',
              hint:
                  'Paste the Firebase service-account JSON from the Firebase Console',
              isConfigured: isSet,
              onSave: (value) async {
                // Validate JSON before encoding.
                try {
                  jsonDecode(value);
                } catch (_) {
                  throw Exception(
                    'Invalid JSON — paste the complete service-account JSON from Firebase Console',
                  );
                }
                // Base64-encode to match FCM_SERVICE_ACCOUNT_JSON_B64 env var format.
                final b64 = base64Encode(utf8.encode(value));
                await ref
                    .read(pushConfigNotifierProvider.notifier)
                    .upsertFcmVaultSecret('fcm_service_account_b64', b64);
                _serviceAccountStatus.value = true;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCardActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: (_dirty && !_saving) ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Changes'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.border,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ── Registered Devices Card ──────────────────────────────────────────────────

  Widget _buildDevicesCard(PushConfigStatus status) {
    final anyActiveDevices = status.activeCountFor('admin') > 0 ||
        status.activeCountFor('customer') > 0 ||
        status.activeCountFor('vendor') > 0;
    final canTest = anyActiveDevices && status.pushSecretIsSet;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDevicesCardHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAppRow(
                  icon: Icons.people_rounded,
                  label: 'Customer App',
                  userType: 'customer',
                  platforms: const ['android', 'ios'],
                  status: status,
                ),
                const SizedBox(height: 10),
                _buildAppRow(
                  icon: Icons.store_rounded,
                  label: 'Vendor App',
                  userType: 'vendor',
                  platforms: const ['android', 'ios'],
                  status: status,
                ),
                const SizedBox(height: 10),
                _buildAppRow(
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'Admin Web',
                  userType: 'admin',
                  platforms: const ['web'],
                  status: status,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(pushConfigNotifierProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canTest ? _sendTestNotification : null,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Test'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.border,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!canTest)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                !anyActiveDevices
                    ? 'Send Test requires at least one registered device (any app).'
                    : 'Send Test requires the Push Function Secret to be configured.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDevicesCardHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
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
            child: const Icon(
              Icons.devices_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registered Devices',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Active FCM tokens by app and platform',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppRow({
    required IconData icon,
    required String label,
    required String userType,
    required List<String> platforms,
    required PushConfigStatus status,
  }) {
    final totalActive = status.activeCountFor(userType);
    final counts = status.countsFor(userType);
    final hasDevices = totalActive > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: hasDevices
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.border,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: hasDevices ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                if (hasDevices)
                  _buildPlatformBadges(platforms, counts)
                else
                  const Text(
                    'No registered devices',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hasDevices
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.border,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$totalActive active',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasDevices ? AppColors.success : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformBadges(
    List<String> platforms,
    List<DeviceTokenCount> counts,
  ) {
    return Wrap(
      spacing: 6,
      children: [
        for (final platform in platforms)
          Builder(
            builder: (context) {
              final count = counts
                  .where((c) => c.platform == platform)
                  .fold(0, (sum, c) => sum + c.activeCount);
              if (count == 0) return const SizedBox.shrink();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_platformLabel(platform)}: $count',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  String _platformLabel(String platform) {
    switch (platform) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'web':
        return 'Web';
      default:
        return platform;
    }
  }

  Widget _buildToggle({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}

// ── Send Test dialog ──────────────────────────────────────────────────────────

enum _TestTarget { admin, customer, vendor }

enum _DialogPhase { loadingRecipients, selecting, sending, done }

class _SendTestDialog extends ConsumerStatefulWidget {
  const _SendTestDialog({required this.status});
  final PushConfigStatus status;

  @override
  ConsumerState<_SendTestDialog> createState() => _SendTestDialogState();
}

class _SendTestDialogState extends ConsumerState<_SendTestDialog> {
  _TestTarget _targetType = _TestTarget.admin;
  _DialogPhase _phase = _DialogPhase.loadingRecipients;
  List<PushTestTarget> _recipients = [];
  PushTestTarget? _selected;
  String? _error;
  ({int sent, int failed})? _result;
  bool _resultPending = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Default to Admin — load admin recipients immediately on open.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadRecipients(_TestTarget.admin));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients(_TestTarget type) async {
    if (!mounted) return;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _phase = _DialogPhase.loadingRecipients;
      _recipients = [];
      _selected = null;
      _error = null;
    });
    try {
      final data = await ref
          .read(pushConfigRepositoryProvider)
          .getPushTestTargets(type.name);
      if (!mounted) return;
      setState(() {
        _recipients = data;
        _selected = data.isNotEmpty ? data.first : null;
        _phase = _DialogPhase.selecting;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load recipients: $e';
        _phase = _DialogPhase.selecting;
      });
    }
  }

  Future<void> _onTargetChanged(_TestTarget type) async {
    if (_phase == _DialogPhase.sending) return;
    setState(() => _targetType = type);
    await _loadRecipients(type);
  }

  Future<void> _send() async {
    final target = _selected;
    if (target == null) {
      setState(() => _error = 'No recipient selected.');
      return;
    }
    setState(() {
      _phase = _DialogPhase.sending;
      _error = null;
    });

    final supabase = ref.read(supabaseClientProvider);
    final repo = ref.read(pushConfigRepositoryProvider);

    try {
      final inserted = await supabase
          .from('notifications')
          .insert({
            'user_type': _targetType.name,
            'user_id': target.userId,
            'title': 'Test Push Notification',
            'message': 'Test notification from DODO Booker admin panel.',
            'notification_type': 'system',
            'is_read': false,
          })
          .select('id')
          .single();

      final notificationId = inserted['id'] as String;

      // Allow Edge Function time to process.
      await Future.delayed(const Duration(milliseconds: 3000));
      if (!mounted) return;

      ({int sent, int failed})? delivery;
      try {
        delivery = await repo.getPushDeliveryResult(notificationId);
      } catch (_) {
        // Treat as pending if result fetch fails.
      }

      if (!mounted) return;
      setState(() {
        _phase = _DialogPhase.done;
        _result = delivery;
        _resultPending = delivery == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _DialogPhase.selecting;
        _error = 'Send failed: $e';
      });
    }
  }

  // ── Content builders ──────────────────────────────────────────────────────────

  Widget _buildSelecting() {
    final adminCount = widget.status.activeCountFor('admin');
    final customerCount = widget.status.activeCountFor('customer');
    final vendorCount = widget.status.activeCountFor('vendor');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select a target type and a specific registered recipient.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        _label('Target'),
        const SizedBox(height: 8),
        _TargetTile(
          label: 'Admin',
          subtitle: _deviceSubtitle(adminCount),
          icon: Icons.admin_panel_settings_rounded,
          value: _TestTarget.admin,
          groupValue: _targetType,
          enabled: adminCount > 0,
          onChanged: _onTargetChanged,
        ),
        const SizedBox(height: 6),
        _TargetTile(
          label: 'Customer',
          subtitle: _deviceSubtitle(customerCount),
          icon: Icons.people_rounded,
          value: _TestTarget.customer,
          groupValue: _targetType,
          enabled: customerCount > 0,
          onChanged: _onTargetChanged,
        ),
        const SizedBox(height: 6),
        _TargetTile(
          label: 'Vendor',
          subtitle: _deviceSubtitle(vendorCount),
          icon: Icons.store_rounded,
          value: _TestTarget.vendor,
          groupValue: _targetType,
          enabled: vendorCount > 0,
          onChanged: _onTargetChanged,
        ),
        const SizedBox(height: 16),
        _label('Recipient'),
        const SizedBox(height: 8),
        _buildRecipientPicker(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _error!),
        ],
      ],
    );
  }

  Widget _buildRecipientPicker() {
    if (_phase == _DialogPhase.loadingRecipients) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_recipients.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'No active registered devices for this target type.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }

    final filtered = _searchQuery.isEmpty
        ? _recipients
        : _recipients
            .where((r) => r.displayName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search field ──────────────────────────────────────────────────
        SizedBox(
          height: 38,
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search by name…',
              prefixIcon: const Icon(Icons.search_rounded, size: 17),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 15),
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // ── Filtered list ─────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No matches for "$_searchQuery".',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  separatorBuilder: (_, idx) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (ctx, i) {
                    final r = filtered[i];
                    final isSelected = r == _selected;
                    final cnt =
                        '${r.activeDeviceCount} device${r.activeDeviceCount == 1 ? '' : 's'}';
                    return InkWell(
                      borderRadius: i == 0
                          ? const BorderRadius.vertical(
                              top: Radius.circular(7))
                          : i == filtered.length - 1
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(7))
                              : BorderRadius.zero,
                      onTap: () => setState(() => _selected = r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.07)
                            : null,
                        child: Row(
                          children: [
                            if (isSelected)
                              const Icon(Icons.check_rounded,
                                  size: 14, color: AppColors.accent)
                            else
                              const SizedBox(width: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.displayName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '$cnt  ·  ${r.platformLabel}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 6),
          Text(
            'Will send to: ${_selected!.displayName}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.accent),
          ),
        ],
      ],
    );
  }

  Widget _buildSending() {
    final name = _selected?.displayName ?? _targetType.name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(
          'Sending to $name…',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Waiting for delivery confirmation…',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDone() {
    if (_resultPending || _result == null) {
      return _doneState(
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        title: 'Delivery queued',
        subtitle:
            'The notification was sent but the delivery result is still pending.\n'
            'Check push_deliveries in the database.',
      );
    }
    final success = _result!.sent > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _doneState(
          icon: success
              ? Icons.check_circle_outline_rounded
              : Icons.cancel_outlined,
          color: success ? AppColors.success : AppColors.error,
          title: success ? 'Delivered' : 'Not delivered',
          subtitle: '${_result!.sent} sent · ${_result!.failed} failed',
        ),
        if (!success && _result!.failed > 0) ...[
          const SizedBox(height: 8),
          const Text(
            'FCM rejected the token(s). They may have been deactivated.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _doneState({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static String _deviceSubtitle(int count) => count == 0
      ? 'No active devices'
      : '$count active device${count == 1 ? '' : 's'}';

  static Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      );

  // ── Dialog scaffold ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Widget content = switch (_phase) {
      _DialogPhase.sending => _buildSending(),
      _DialogPhase.done => _buildDone(),
      _ => _buildSelecting(),
    };

    final List<Widget> actions = switch (_phase) {
      _DialogPhase.done => [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Done'),
          ),
        ],
      _DialogPhase.sending => const [],
      _ => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: (_phase == _DialogPhase.loadingRecipients ||
                    _selected == null)
                ? null
                : _send,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send Test'),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
    };

    return AlertDialog(
      title: const Text('Send Test Notification'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(width: 420, child: content),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: actions,
    );
  }
}

// ── Target radio tile ─────────────────────────────────────────────────────────

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final _TestTarget value;
  final _TestTarget groupValue;
  final bool enabled;
  final ValueChanged<_TestTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue && enabled;
    return GestureDetector(
      onTap: enabled ? () => onChanged(value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.06)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _RadioDot(selected: selected, enabled: enabled),
            const SizedBox(width: 10),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : AppColors.border,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                size: 14,
                color: enabled ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Radio dot (replaces deprecated Radio widget) ──────────────────────────────

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.enabled});
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.accent : AppColors.textSecondary;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : AppColors.border,
          width: selected ? 0 : 1.5,
        ),
        color: selected ? color : Colors.transparent,
      ),
      child: selected
          ? const Center(
              child: SizedBox(
                width: 8,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 15, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
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
              'Failed to load push notification status',
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
