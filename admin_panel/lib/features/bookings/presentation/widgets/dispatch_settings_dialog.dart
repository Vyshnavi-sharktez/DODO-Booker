import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/dispatch_providers.dart';
import '../../domain/models/dispatch_settings.dart';

class DispatchSettingsDialog extends ConsumerStatefulWidget {
  const DispatchSettingsDialog({super.key});

  @override
  ConsumerState<DispatchSettingsDialog> createState() =>
      _DispatchSettingsDialogState();
}

class _DispatchSettingsDialogState
    extends ConsumerState<DispatchSettingsDialog> {
  final _formKey = GlobalKey<FormState>();

  late bool _isEnabled;
  late TextEditingController _timeoutController;
  late TextEditingController _maxAttemptsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settingsAsync = ref.read(dispatchSettingsNotifierProvider);
    final settings = settingsAsync.valueOrNull ??
        const DispatchSettings(
          id: '',
          isTierDispatchEnabled: true,
          tierTimeoutSeconds: 60,
          maxAttemptsPerTier: 1,
        );

    _isEnabled = settings.isTierDispatchEnabled;
    _timeoutController = TextEditingController(
      text: settings.tierTimeoutSeconds.toString(),
    );
    _maxAttemptsController = TextEditingController(
      text: settings.maxAttemptsPerTier.toString(),
    );
  }

  @override
  void dispose() {
    _timeoutController.dispose();
    _maxAttemptsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final current = ref.read(dispatchSettingsNotifierProvider).valueOrNull ??
          const DispatchSettings(
            id: '',
            isTierDispatchEnabled: true,
            tierTimeoutSeconds: 60,
            maxAttemptsPerTier: 1,
          );

      final updated = current.copyWith(
        isTierDispatchEnabled: _isEnabled,
        tierTimeoutSeconds: int.parse(_timeoutController.text.trim()),
        maxAttemptsPerTier: int.parse(_maxAttemptsController.text.trim()),
      );

      await ref
          .read(dispatchSettingsNotifierProvider.notifier)
          .updateSettings(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dispatch settings saved successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.settings_suggest_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sequential Tier Dispatch Settings',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'Configure automatic tier escalation & timeouts',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Form Body
            Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Enable Auto Dispatch Switch
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SwitchListTile(
                        value: _isEnabled,
                        onChanged: (val) => setState(() => _isEnabled = val),
                        activeTrackColor: AppColors.primary,
                        title: const Text(
                          'Enable Sequential Tier Dispatch',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Automatically offer bookings to higher-tier vendors first before escalating to lower tiers.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Timeout in Seconds
                    TextFormField(
                      controller: _timeoutController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Tier Response Timeout (Seconds) *',
                        hintText: 'e.g. 60',
                        prefixIcon: Icon(Icons.timer_rounded),
                        helperText:
                            'Time to wait for a vendor to respond before escalating to the next tier vendor.',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Timeout duration is required';
                        }
                        final parsed = int.tryParse(v.trim());
                        if (parsed == null || parsed < 10 || parsed > 3600) {
                          return 'Enter a valid timeout (10 - 3600 seconds)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Max Attempts per Tier
                    TextFormField(
                      controller: _maxAttemptsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Max Attempts Per Tier *',
                        hintText: 'e.g. 1',
                        prefixIcon: Icon(Icons.format_list_numbered_rounded),
                        helperText:
                            'Maximum number of vendors to try per tier level before advancing.',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Max attempts count is required';
                        }
                        final parsed = int.tryParse(v.trim());
                        if (parsed == null || parsed < 1) {
                          return 'Enter a valid count (≥ 1)';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save Settings'),
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
