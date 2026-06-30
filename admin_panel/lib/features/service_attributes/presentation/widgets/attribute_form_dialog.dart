import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/service_attribute.dart';

const _fieldTypes = [
  ('text', 'Text', Icons.text_fields_rounded),
  ('number', 'Number', Icons.numbers_rounded),
  ('dropdown', 'Dropdown', Icons.arrow_drop_down_circle_outlined),
  ('radio', 'Radio', Icons.radio_button_checked_rounded),
  ('checkbox', 'Checkbox', Icons.check_box_outlined),
];

class AttributeFormDialog extends StatefulWidget {
  final ServiceAttribute? existing;
  final String serviceId;
  final String serviceName;
  final Future<void> Function({
    required String serviceId,
    required String name,
    required String fieldType,
    required bool isRequired,
  }) onSave;

  const AttributeFormDialog({
    super.key,
    this.existing,
    required this.serviceId,
    required this.serviceName,
    required this.onSave,
  });

  @override
  State<AttributeFormDialog> createState() => _AttributeFormDialogState();
}

class _AttributeFormDialogState extends State<AttributeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _fieldType;
  late bool _isRequired;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _fieldType = e?.fieldType ?? 'text';
    _isRequired = e?.isRequired ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        serviceId: widget.serviceId,
        name: _name.text.trim(),
        fieldType: _fieldType,
        isRequired: _isRequired,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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
    final isEdit = widget.existing != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEdit
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Attribute' : 'New Attribute',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Service — read-only context
                      _ContextRow(
                        label: 'Service',
                        name: widget.serviceName,
                        icon: Icons.miscellaneous_services_rounded,
                      ),
                      const SizedBox(height: 16),

                      // Attribute Name
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Attribute Name *',
                          hintText: 'e.g. Number of Rooms',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Field Type
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _fieldType,
                        decoration: const InputDecoration(
                          labelText: 'Field Type *',
                        ),
                        items: _fieldTypes
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.$1,
                                child: Row(
                                  children: [
                                    Icon(t.$3,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 10),
                                    Text(t.$2),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _fieldType = v);
                        },
                        validator: (v) =>
                            v == null ? 'Please select a type' : null,
                        isExpanded: true,
                      ),
                      if (_fieldType == 'dropdown' ||
                          _fieldType == 'radio' ||
                          _fieldType == 'checkbox') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Text(
                              'You can manage options after saving.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Required toggle
                      _ToggleRow(
                        icon: Icons.star_outline_rounded,
                        activeIcon: Icons.star_rounded,
                        label: 'Required',
                        value: _isRequired,
                        activeColor: AppColors.warning,
                        onChanged: (v) => setState(() => _isRequired = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Create Attribute'),
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

class _ContextRow extends StatelessWidget {
  final String label;
  final String name;
  final IconData icon;

  const _ContextRow({
    required this.label,
    required this.name,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.lock_outline, size: 13, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            value ? activeIcon : icon,
            color: value ? activeColor : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
          ),
        ],
      ),
    );
  }
}
