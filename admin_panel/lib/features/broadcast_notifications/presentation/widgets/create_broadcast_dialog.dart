import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../service_availability_areas/application/providers/service_availability_areas_providers.dart';
import '../../application/providers/broadcast_notifications_providers.dart';

// ── Targeting type options per audience ──────────────────────────────────────

List<({String value, String label})> _targetingOptionsFor(String audience) {
  return [
    (value: 'all', label: 'All ${audience == 'vendors' ? 'Vendors' : audience == 'customers' ? 'Customers' : 'Users'}'),
    (value: 'serving_area', label: 'By Serving Area'),
    if (audience == 'customers') ...[
      (value: 'booked_service', label: 'By Booked Service'),
      (value: 'booked_category', label: 'By Category'),
    ],
  ];
}

// ── CreateBroadcastDialog ─────────────────────────────────────────────────────

class CreateBroadcastDialog extends ConsumerStatefulWidget {
  const CreateBroadcastDialog({super.key});

  @override
  ConsumerState<CreateBroadcastDialog> createState() =>
      _CreateBroadcastDialogState();
}

class _CreateBroadcastDialogState extends ConsumerState<CreateBroadcastDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _deepLinkCtrl = TextEditingController();

  String _audience = 'customers';
  String _notificationType = 'announcement';
  String _targetingType = 'all';
  String? _targetingValue;
  String? _targetingLabel;
  bool _scheduleForLater = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  bool _showOptional = false;
  bool _savingDraft = false;
  bool _sending = false;

  List<({String value, String label})> _targetingValues = [];
  bool _loadingTargetingValues = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _imageUrlCtrl.dispose();
    _deepLinkCtrl.dispose();
    super.dispose();
  }

  // ── Targeting value fetch ─────────────────────────────────────────────────

  Future<void> _loadTargetingValues() async {
    if (_targetingType == 'all') {
      setState(() {
        _targetingValues = [];
        _targetingValue = null;
        _targetingLabel = null;
      });
      return;
    }
    setState(() {
      _loadingTargetingValues = true;
      _targetingValue = null;
      _targetingLabel = null;
    });
    try {
      final List<({String value, String label})> options;
      if (_targetingType == 'serving_area') {
        final areas =
            await ref.read(serviceAvailabilityAreasRepositoryProvider).fetchAll();
        options = [
          (value: 'all_areas', label: 'All active serving areas'),
          ...areas.where((a) => a.isActive).map((a) => (value: a.id, label: a.name)),
        ];
      } else {
        options = await ref.read(broadcastNotificationsRepositoryProvider).getTargetingOptions(
          targetingType: _targetingType,
          audience: _audience,
        );
      }
      if (mounted) {
        setState(() {
          _targetingValues = options;
          _loadingTargetingValues = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTargetingValues = false);
    }
  }

  void _onAudienceChanged(String audience) {
    setState(() {
      _audience = audience;
      // Reset targeting if it's no longer valid for the new audience
      final valid = _targetingOptionsFor(audience).map((o) => o.value).toSet();
      if (!valid.contains(_targetingType)) {
        _targetingType = 'all';
        _targetingValue = null;
        _targetingLabel = null;
        _targetingValues = [];
      }
    });
    if (_targetingType != 'all') _loadTargetingValues();
  }

  void _onTargetingTypeChanged(String type) {
    setState(() {
      _targetingType = type;
      _targetingValue = null;
      _targetingLabel = null;
    });
    _loadTargetingValues();
  }

  // ── Date / time pickers ───────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) setState(() => _scheduledTime = picked);
  }

  // 'all_areas' is a UI-only sentinel so the dropdown can show the selection.
  // The DB targeting_value must be NULL (not the string) for "all active areas".
  String? get _dbTargetingValue =>
      _targetingType == 'serving_area' && _targetingValue == 'all_areas'
          ? null
          : _targetingValue;

  DateTime? get _scheduledAt {
    if (_scheduledDate == null) return null;
    final time = _scheduledTime ?? TimeOfDay.now();
    return DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      time.hour,
      time.minute,
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit({required bool draft}) async {
    if (!_formKey.currentState!.validate()) return;
    if (!draft && _scheduleForLater && _scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date and time to schedule.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_targetingType != 'all' && _targetingValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a targeting value.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final status = draft
        ? 'draft'
        : (_scheduleForLater ? 'scheduled' : 'draft');

    if (draft) {
      setState(() => _savingDraft = true);
    } else {
      setState(() => _sending = true);
    }

    try {
      final notifier =
          ref.read(broadcastNotificationsNotifierProvider.notifier);

      if (draft || _scheduleForLater) {
        await notifier.createBroadcast(
          title: _titleCtrl.text.trim(),
          message: _messageCtrl.text.trim(),
          notificationType: _notificationType,
          audience: _audience,
          imageUrl: _imageUrlCtrl.text.trim().isEmpty ? null : _imageUrlCtrl.text.trim(),
          deepLink: _deepLinkCtrl.text.trim().isEmpty ? null : _deepLinkCtrl.text.trim(),
          targetingType: _targetingType,
          targetingValue: _dbTargetingValue,
          targetingLabel: _targetingLabel,
          status: status,
          scheduledAt: _scheduleForLater ? _scheduledAt : null,
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        // Create as draft first, then send immediately
        final created = await notifier.createBroadcast(
          title: _titleCtrl.text.trim(),
          message: _messageCtrl.text.trim(),
          notificationType: _notificationType,
          audience: _audience,
          imageUrl: _imageUrlCtrl.text.trim().isEmpty ? null : _imageUrlCtrl.text.trim(),
          deepLink: _deepLinkCtrl.text.trim().isEmpty ? null : _deepLinkCtrl.text.trim(),
          targetingType: _targetingType,
          targetingValue: _dbTargetingValue,
          targetingLabel: _targetingLabel,
          status: 'draft',
          scheduledAt: null,
        );
        final count = await notifier.sendBroadcast(created.id);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                count == 1
                    ? 'Notification sent to 1 recipient.'
                    : 'Notification sent to $count recipient${count == 1 ? '' : 's'}.',
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              width: 360,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
        setState(() {
          _savingDraft = false;
          _sending = false;
        });
      }
    }
  }

  // ── Builders ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy = _savingDraft || _sending;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAudienceSection(),
                      const SizedBox(height: 20),
                      _buildTypeSection(),
                      const SizedBox(height: 20),
                      _buildTitleField(),
                      const SizedBox(height: 16),
                      _buildMessageField(),
                      const SizedBox(height: 20),
                      _buildTargetingSection(),
                      const SizedBox(height: 20),
                      _buildOptionalSection(),
                      const SizedBox(height: 20),
                      _buildScheduleSection(),
                    ],
                  ),
                ),
              ),
            ),
            _buildFooter(busy),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Text(
            'Create Notification',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
      );

  // ── Audience ──────────────────────────────────────────────────────────────

  Widget _buildAudienceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('AUDIENCE'),
        Row(
          children: [
            for (final opt in [
              ('customers', 'Customers', Icons.people_rounded),
              ('vendors', 'Vendors', Icons.store_rounded),
              ('both', 'Both', Icons.groups_rounded),
            ])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: opt.$1 == 'both' ? 0 : 8),
                  child: _AudienceChip(
                    label: opt.$2,
                    icon: opt.$3,
                    selected: _audience == opt.$1,
                    onTap: () => _onAudienceChanged(opt.$1),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Notification type ─────────────────────────────────────────────────────

  Widget _buildTypeSection() {
    const types = [
      ('offer', 'Offer'),
      ('new_service', 'New Service'),
      ('announcement', 'Announcement'),
      ('custom', 'Custom'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('NOTIFICATION TYPE'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in types)
              _TypeChip(
                label: t.$2,
                selected: _notificationType == t.$1,
                onTap: () => setState(() => _notificationType = t.$1),
              ),
          ],
        ),
      ],
    );
  }

  // ── Title ─────────────────────────────────────────────────────────────────

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleCtrl,
      decoration: const InputDecoration(
        labelText: 'Title *',
        hintText: 'e.g. Exclusive Offer This Weekend!',
        prefixIcon: Icon(Icons.title_rounded),
      ),
      textCapitalization: TextCapitalization.sentences,
      maxLength: 100,
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Title is required' : null,
    );
  }

  // ── Message ───────────────────────────────────────────────────────────────

  Widget _buildMessageField() {
    return TextFormField(
      controller: _messageCtrl,
      decoration: const InputDecoration(
        labelText: 'Message *',
        hintText: 'Write your notification message here…',
        prefixIcon: Icon(Icons.message_rounded),
        alignLabelWithHint: true,
      ),
      maxLines: 3,
      maxLength: 300,
      textCapitalization: TextCapitalization.sentences,
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Message is required' : null,
    );
  }

  // ── Targeting ─────────────────────────────────────────────────────────────

  Widget _buildTargetingSection() {
    final options = _targetingOptionsFor(_audience);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('TARGETING'),
        DropdownButtonFormField<String>(
          value: _targetingType,
          decoration: const InputDecoration(
            labelText: 'Target Audience',
            prefixIcon: Icon(Icons.filter_alt_rounded),
          ),
          items: options
              .map((o) => DropdownMenuItem(
                    value: o.value,
                    child: Text(o.label),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) _onTargetingTypeChanged(v);
          },
        ),
        if (_targetingType != 'all') ...[
          const SizedBox(height: 12),
          _loadingTargetingValues
              ? const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : _targetingValues.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'No values found for selected targeting.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      value: _targetingValue,
                      hint: _targetingType == 'serving_area'
                          ? const Text('Select serving area')
                          : null,
                      decoration: InputDecoration(
                        labelText: _targetingTypeLabel(_targetingType),
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                      items: _targetingValues
                          .map((o) => DropdownMenuItem(
                                value: o.value,
                                child: Text(
                                  o.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          final label = _targetingValues
                              .firstWhere((o) => o.value == v)
                              .label;
                          setState(() {
                            _targetingValue = v;
                            _targetingLabel = label;
                          });
                        }
                      },
                      validator: (v) => v == null ? 'Select a value' : null,
                    ),
        ],
      ],
    );
  }

  String _targetingTypeLabel(String type) => switch (type) {
        'serving_area' => 'Serving Area',
        'booked_service' => 'Service',
        'booked_category' => 'Category',
        _ => 'Value',
      };

  // ── Optional fields ───────────────────────────────────────────────────────

  Widget _buildOptionalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showOptional = !_showOptional),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showOptional
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _showOptional
                      ? 'Hide optional fields'
                      : 'Add image or deep link (optional)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showOptional) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _imageUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Image URL',
              hintText: 'https://…',
              prefixIcon: Icon(Icons.image_rounded),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _deepLinkCtrl,
            decoration: const InputDecoration(
              labelText: 'Deep Link / Action URL',
              hintText: 'e.g. dodo://services or https://…',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            keyboardType: TextInputType.url,
          ),
        ],
      ],
    );
  }

  // ── Schedule ──────────────────────────────────────────────────────────────

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                    const Text(
                      'Schedule for later',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Set a specific date and time to send',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _scheduleForLater,
                onChanged: (v) => setState(() => _scheduleForLater = v),
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
        ),
        if (_scheduleForLater) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateTimePickerTile(
                  icon: Icons.calendar_today_rounded,
                  label: _scheduledDate == null
                      ? 'Pick date'
                      : '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}',
                  onTap: _pickDate,
                  filled: _scheduledDate != null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTimePickerTile(
                  icon: Icons.access_time_rounded,
                  label: _scheduledTime == null
                      ? 'Pick time'
                      : _scheduledTime!.format(context),
                  onTap: _pickTime,
                  filled: _scheduledTime != null,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter(bool busy) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          const Spacer(),
          TextButton(
            onPressed: busy ? null : () => _submit(draft: true),
            child: _savingDraft
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Draft'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy ? null : () => _submit(draft: false),
            icon: _sending
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    _scheduleForLater
                        ? Icons.schedule_send_rounded
                        : Icons.send_rounded,
                    size: 16,
                  ),
            label: Text(_scheduleForLater ? 'Schedule' : 'Send Now'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _AudienceChip ─────────────────────────────────────────────────────────────

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _TypeChip ─────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── _DateTimePickerTile ───────────────────────────────────────────────────────

class _DateTimePickerTile extends StatelessWidget {
  const _DateTimePickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: filled
              ? AppColors.accent.withValues(alpha: 0.06)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: filled ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: filled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      filled ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
