import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/campaigns_providers.dart';

// ── Targeting option record ───────────────────────────────────────────────────

typedef _TargetOption = ({String value, String label});

// ── Dialog ────────────────────────────────────────────────────────────────────

class CreateCampaignDialog extends ConsumerStatefulWidget {
  const CreateCampaignDialog({super.key});

  @override
  ConsumerState<CreateCampaignDialog> createState() =>
      _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends ConsumerState<CreateCampaignDialog> {
  int _step = 0; // 0=Compose, 1=Audience, 2=Review

  // Step 1
  final _nameCtrl = TextEditingController();
  final _templateIdCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey1 = GlobalKey<FormState>();

  // Step 2
  bool _isTestMode = true; // safe default
  String _targetingType = 'all';
  String? _targetingValue;
  String? _targetingLabel;
  List<_TargetOption> _targetingOptions = [];
  bool _loadingOptions = false;

  // Preview count
  int? _previewCount;
  List<String> _previewSample = [];
  bool _loadingCount = false;

  // Sending
  bool _sending = false;

  static const double _estimatedSmsRateRupees = 0.15;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _templateIdCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  // ── Step navigation ───────────────────────────────────────────────────────

  bool _validateStep0() => _formKey1.currentState?.validate() ?? false;

  void _next() {
    if (_step == 0 && !_validateStep0()) return;
    setState(() => _step++);
    if (_step == 1) _loadTargetingOptions();
  }

  void _back() => setState(() => _step--);

  // ── Targeting options ─────────────────────────────────────────────────────

  Future<void> _loadTargetingOptions() async {
    if (_targetingType == 'all') return;
    setState(() => _loadingOptions = true);
    try {
      final repo = ref.read(campaignsRepositoryProvider);
      final opts = await repo.getTargetingOptions(targetingType: _targetingType);
      if (mounted) {
        setState(() {
          _targetingOptions = opts;
          _targetingValue = null;
          _targetingLabel = null;
          _previewCount = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _previewRecipients() async {
    if (!_isTestMode && _targetingType != 'all' && _targetingValue == null) return;
    setState(() { _loadingCount = true; _previewCount = null; });
    try {
      final repo = ref.read(campaignsRepositoryProvider);
      if (_isTestMode) {
        setState(() {
          _previewCount = 1;
          _previewSample = ['(test phone configured in SMS / OTP settings)'];
          _loadingCount = false;
        });
        return;
      }
      final result = await repo.getRecipientCount(
        channel: 'sms',
        targetingType: _targetingType,
        targetingValue: _targetingValue,
      );
      if (mounted) {
        setState(() {
          _previewCount = result.count;
          _previewSample = result.sampleMasked;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Preview failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingCount = false);
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final campaignId = await ref.read(campaignsNotifierProvider.notifier)
          .createCampaign(
            name: _nameCtrl.text.trim(),
            channel: 'sms',
            message: _messageCtrl.text.trim(),
            templateId: _templateIdCtrl.text.trim(),
            templateLanguage: 'en',
            targetingType: _targetingType,
            targetingValue: _targetingType == 'all' ? null : _targetingValue,
            targetingLabel: _targetingType == 'all' ? null : _targetingLabel,
            isTestMode: _isTestMode,
            estimatedCount: _isTestMode ? 1 : _previewCount,
          );

      final result = await ref.read(campaignsNotifierProvider.notifier)
          .sendSmsCampaign(campaignId);

      if (mounted) {
        Navigator.of(context).pop();
        final sentCount = result['sent_count'] as int? ?? 0;
        final isTest = result['is_test_mode'] as bool? ?? true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            isTest
                ? 'Test SMS submitted to MSG91 ($sentCount message). Check your test phone.'
                : 'Campaign submitted to MSG91. $sentCount message(s) queued for delivery.',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Send failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: switch (_step) {
                    0 => _Step0Compose(
                        key: const ValueKey(0),
                        nameCtrl: _nameCtrl,
                        templateIdCtrl: _templateIdCtrl,
                        messageCtrl: _messageCtrl,
                        formKey: _formKey1,
                      ),
                    1 => _Step1Audience(
                        key: const ValueKey(1),
                        isTestMode: _isTestMode,
                        targetingType: _targetingType,
                        targetingValue: _targetingValue,
                        targetingLabel: _targetingLabel,
                        targetingOptions: _targetingOptions,
                        loadingOptions: _loadingOptions,
                        previewCount: _previewCount,
                        previewSample: _previewSample,
                        loadingCount: _loadingCount,
                        onTestModeChanged: (v) {
                          setState(() {
                            _isTestMode = v;
                            _previewCount = null;
                          });
                        },
                        onTargetingTypeChanged: (v) {
                          setState(() {
                            _targetingType = v;
                            _targetingValue = null;
                            _targetingLabel = null;
                            _targetingOptions = [];
                            _previewCount = null;
                          });
                          _loadTargetingOptions();
                        },
                        onTargetingValueChanged: (value, label) {
                          setState(() {
                            _targetingValue = value;
                            _targetingLabel = label;
                            _previewCount = null;
                          });
                        },
                        onPreview: _previewRecipients,
                      ),
                    _ => _Step2Review(
                        key: const ValueKey(2),
                        name: _nameCtrl.text.trim(),
                        templateId: _templateIdCtrl.text.trim(),
                        message: _messageCtrl.text.trim(),
                        isTestMode: _isTestMode,
                        targetingType: _targetingType,
                        targetingLabel: _targetingLabel,
                        previewCount: _isTestMode ? 1 : _previewCount,
                        estimatedRateRupees: _estimatedSmsRateRupees,
                      ),
                  },
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sms_rounded, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'New SMS Campaign',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: _sending ? null : () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['Compose', 'Audience', 'Review'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(
                height: 2,
                color: i ~/ 2 < _step
                    ? AppColors.primary
                    : AppColors.border,
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < _step;
          final active = idx == _step;
          return Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || active ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: done || active ? AppColors.primary : AppColors.border,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[idx],
                style: TextStyle(
                  fontSize: 10,
                  color: active ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildFooter() {
    final isLastStep = _step == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_step > 0)
            TextButton(
              onPressed: _sending ? null : _back,
              child: const Text('Back'),
            )
          else
            const SizedBox(),
          Row(
            children: [
              if (!isLastStep)
                FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Next'),
                )
              else
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(_sending ? 'Sending…' : 'Send Campaign'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _isTestMode ? AppColors.primary : AppColors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 0: Compose ───────────────────────────────────────────────────────────

class _Step0Compose extends StatelessWidget {
  const _Step0Compose({
    super.key,
    required this.nameCtrl,
    required this.templateIdCtrl,
    required this.messageCtrl,
    required this.formKey,
  });

  final TextEditingController nameCtrl;
  final TextEditingController templateIdCtrl;
  final TextEditingController messageCtrl;
  final GlobalKey<FormState> formKey;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _field(
            label: 'Campaign Name',
            hint: 'e.g. Diwali Offer 2026',
            ctrl: nameCtrl,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _field(
            label: 'MSG91 Flow Template ID',
            hint: 'Flow template ID from your MSG91 dashboard',
            ctrl: templateIdCtrl,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 4),
          _infoBox(
            'Enter the Flow template ID (not the DLT template ID). '
            'This template must be pre-registered in MSG91 and approved by DLT. '
            'Variables in the template body (e.g. #var1#) are sent as-is without substitution in this version.',
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Message Preview (reference)',
            hint: 'Describe the message content — this is for your records only, not sent to MSG91',
            ctrl: messageCtrl,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController ctrl,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _infoBox(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

// ── Step 1: Audience ──────────────────────────────────────────────────────────

class _Step1Audience extends StatelessWidget {
  const _Step1Audience({
    super.key,
    required this.isTestMode,
    required this.targetingType,
    required this.targetingValue,
    required this.targetingLabel,
    required this.targetingOptions,
    required this.loadingOptions,
    required this.previewCount,
    required this.previewSample,
    required this.loadingCount,
    required this.onTestModeChanged,
    required this.onTargetingTypeChanged,
    required this.onTargetingValueChanged,
    required this.onPreview,
  });

  final bool isTestMode;
  final String targetingType;
  final String? targetingValue;
  final String? targetingLabel;
  final List<({String value, String label})> targetingOptions;
  final bool loadingOptions;
  final int? previewCount;
  final List<String> previewSample;
  final bool loadingCount;
  final ValueChanged<bool> onTestModeChanged;
  final ValueChanged<String> onTargetingTypeChanged;
  final void Function(String value, String label) onTargetingValueChanged;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildModeToggle(),
        const SizedBox(height: 20),
        if (!isTestMode) ...[
          _buildTargeting(),
          const SizedBox(height: 16),
          _buildPreviewButton(),
          if (previewCount != null) ...[
            const SizedBox(height: 12),
            _buildPreviewResult(),
          ],
        ],
        if (isTestMode) _buildTestModeInfo(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Send Mode',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                label: 'Test Mode',
                description: 'Send only to your configured test phone',
                icon: Icons.science_outlined,
                selected: isTestMode,
                onTap: () => onTestModeChanged(true),
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                label: 'Live Mode',
                description: 'Send to all eligible customers',
                icon: Icons.send_rounded,
                selected: !isTestMode,
                onTap: () => onTestModeChanged(false),
                color: AppColors.error,
              ),
            ),
          ],
        ),
        if (!isTestMode) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Live mode sends real SMS messages to all eligible customers. '
                    'Costs apply per message submitted to MSG91.',
                    style: TextStyle(fontSize: 11, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTestModeInfo() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 16, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Test mode is active',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                SizedBox(height: 4),
                Text(
                  'The SMS will be sent only to the test phone number configured in '
                  'SMS / OTP Configuration → MSG91 → Test Phone. '
                  'No customers will be contacted.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargeting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Audience',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: targetingType,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All eligible customers')),
            DropdownMenuItem(value: 'city', child: Text('Customers in a city')),
            DropdownMenuItem(value: 'booked_service', child: Text('Customers who booked a service')),
            DropdownMenuItem(value: 'booked_category', child: Text('Customers who booked a category')),
          ],
          onChanged: (v) { if (v != null) onTargetingTypeChanged(v); },
        ),
        if (targetingType != 'all') ...[
          const SizedBox(height: 12),
          loadingOptions
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ))
              : targetingOptions.isEmpty
                  ? const Text(
                      'No options available',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    )
                  : DropdownButtonFormField<String>(
                      value: targetingValue,
                      hint: const Text('Select…'),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: targetingOptions
                          .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final opt = targetingOptions.firstWhere((o) => o.value == v);
                        onTargetingValueChanged(v, opt.label);
                      },
                    ),
        ],
      ],
    );
  }

  Widget _buildPreviewButton() {
    final canPreview = targetingType == 'all' || targetingValue != null;
    return OutlinedButton.icon(
      onPressed: canPreview && !loadingCount ? onPreview : null,
      icon: loadingCount
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.people_outline_rounded, size: 16),
      label: Text(loadingCount ? 'Counting…' : 'Preview Recipients'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Widget _buildPreviewResult() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                '$previewCount eligible recipient${previewCount == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success),
              ),
            ],
          ),
          if (previewSample.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Sample: ${previewSample.join(', ')}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: selected ? color : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? color : AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(description,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Step 2: Review & Confirm ──────────────────────────────────────────────────

class _Step2Review extends StatelessWidget {
  const _Step2Review({
    super.key,
    required this.name,
    required this.templateId,
    required this.message,
    required this.isTestMode,
    required this.targetingType,
    required this.targetingLabel,
    required this.previewCount,
    required this.estimatedRateRupees,
  });

  final String name;
  final String templateId;
  final String message;
  final bool isTestMode;
  final String targetingType;
  final String? targetingLabel;
  final int? previewCount;
  final double estimatedRateRupees;

  String get _audienceLabel {
    if (isTestMode) return 'Test phone only';
    return switch (targetingType) {
      'all' => 'All eligible customers',
      'city' => 'City: ${targetingLabel ?? '—'}',
      'booked_service' => 'Booked service: ${targetingLabel ?? '—'}',
      'booked_category' => 'Booked category: ${targetingLabel ?? '—'}',
      _ => targetingType,
    };
  }

  String get _costEstimate {
    if (isTestMode) return '~₹${estimatedRateRupees.toStringAsFixed(2)} (1 message)';
    if (previewCount == null || previewCount == 0) return '—';
    final total = previewCount! * estimatedRateRupees;
    return '~₹${total.toStringAsFixed(2)} ($previewCount × ₹${estimatedRateRupees.toStringAsFixed(2)}/SMS)';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _row('Campaign', name),
        _row('Channel', 'SMS (MSG91 Flow API)'),
        _row('Template ID', templateId),
        if (message.isNotEmpty) _row('Message preview', message),
        _row('Audience', _audienceLabel),
        _row('Recipients', isTestMode ? '1 (test mode)' : '${previewCount ?? '—'}'),
        _row('Estimated cost', _costEstimate),
        const SizedBox(height: 16),
        _buildConfirmBanner(),
        const SizedBox(height: 4),
        _buildDeliveryNote(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmBanner() {
    if (isTestMode) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.science_outlined, size: 16, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Test mode: this will send one real SMS to your configured test phone. '
                'No customer data is used.',
                style: TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live mode: this will submit real SMS messages to MSG91 for delivery '
              'to all eligible customers. This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryNote() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reported count reflects messages submitted to MSG91, not confirmed delivered to handsets. '
              'Actual delivery depends on DLT registration, DND status, and operator routing.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
