import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/instahelp_activity.dart';

class ActivityFormDialog extends StatefulWidget {
  final InstaHelpActivity? existing;
  final Future<void> Function({
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) onSave;

  const ActivityFormDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<ActivityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late List<String> _includedItems;
  late List<String> _excludedItems;
  bool _addingIncluded = false;
  bool _addingExcluded = false;
  late final TextEditingController _newIncludedCtrl;
  late final TextEditingController _newExcludedCtrl;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _includedItems = List.from(e?.includedItems ?? []);
    _excludedItems = List.from(e?.excludedItems ?? []);
    _newIncludedCtrl = TextEditingController();
    _newExcludedCtrl = TextEditingController();
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _newIncludedCtrl.dispose();
    _newExcludedCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        title: _title.text.trim(),
        includedItems: List.from(_includedItems),
        excludedItems: List.from(_excludedItems),
        isActive: _isActive,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Item row (edit + remove inline) ───────────────────────────────────────

  Widget _buildItemRow(
    String text, {
    required VoidCallback onRemove,
    required void Function(String updated) onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
          GestureDetector(
            onTap: () async {
              final ctrl = TextEditingController(text: text);
              final updated = await showDialog<String>(
                context: context,
                builder: (ctx) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: SizedBox(
                    width: 400,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Edit item',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: ctrl,
                            autofocus: true,
                            maxLines: null,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onSubmitted: (v) => Navigator.of(ctx)
                                .pop(v.trim().isEmpty ? null : v.trim()),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(null),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  final v = ctrl.text.trim();
                                  Navigator.of(ctx).pop(v.isEmpty ? null : v);
                                },
                                child: const Text('Save',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              ctrl.dispose();
              if (updated != null) onEdit(updated);
            },
            child: const Icon(Icons.edit_outlined,
                size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: SizedBox(
                    width: 400,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Remove item?',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Remove "$text"?',
                              style: const TextStyle(fontSize: 13),
                              softWrap: true),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    visualDensity: VisualDensity.compact),
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                child: const Text('Remove',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              if (confirmed == true) onRemove();
            },
            child: const Icon(Icons.close_rounded,
                size: 16, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineInput({
    required TextEditingController ctrl,
    required VoidCallback onAdd,
    required VoidCallback onCancel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter item...',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.border, width: 0.8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.border, width: 0.8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onAdd, child: const Text('Add')),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }

  // ── Section header (matches catalog_node_form_dialog style) ───────────────

  Widget _buildSectionHeader(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Activity Group' : 'Add Activity Group',
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

            // Form body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Activity title
                      TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Activity Title *',
                          hintText: 'e.g. Kitchen',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),

                      // ── Included Items ─────────────────────────────────
                      _buildSectionHeader(
                        Icons.check_circle_outline_rounded,
                        'Included Items',
                        AppColors.success,
                      ),
                      ..._includedItems.asMap().entries.map(
                            (e) => _buildItemRow(
                              e.value,
                              onRemove: () => setState(
                                  () => _includedItems.removeAt(e.key)),
                              onEdit: (v) =>
                                  setState(() => _includedItems[e.key] = v),
                            ),
                          ),
                      if (_includedItems.isEmpty && !_addingIncluded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('No items yet.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                      if (_addingIncluded)
                        _buildInlineInput(
                          ctrl: _newIncludedCtrl,
                          onAdd: () {
                            final v = _newIncludedCtrl.text.trim();
                            if (v.isNotEmpty) {
                              setState(() {
                                _includedItems.add(v);
                                _newIncludedCtrl.clear();
                                _addingIncluded = false;
                              });
                            }
                          },
                          onCancel: () => setState(() {
                            _newIncludedCtrl.clear();
                            _addingIncluded = false;
                          }),
                        ),
                      if (!_addingIncluded)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _addingIncluded = true),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 4),
                            child: Text(
                              '+ Add included item',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),

                      // ── Excluded Items ─────────────────────────────────
                      _buildSectionHeader(
                        Icons.do_not_disturb_alt_rounded,
                        'Excluded Items',
                        AppColors.error,
                      ),
                      ..._excludedItems.asMap().entries.map(
                            (e) => _buildItemRow(
                              e.value,
                              onRemove: () => setState(
                                  () => _excludedItems.removeAt(e.key)),
                              onEdit: (v) =>
                                  setState(() => _excludedItems[e.key] = v),
                            ),
                          ),
                      if (_excludedItems.isEmpty && !_addingExcluded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('No items yet.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                      if (_addingExcluded)
                        _buildInlineInput(
                          ctrl: _newExcludedCtrl,
                          onAdd: () {
                            final v = _newExcludedCtrl.text.trim();
                            if (v.isNotEmpty) {
                              setState(() {
                                _excludedItems.add(v);
                                _newExcludedCtrl.clear();
                                _addingExcluded = false;
                              });
                            }
                          },
                          onCancel: () => setState(() {
                            _newExcludedCtrl.clear();
                            _addingExcluded = false;
                          }),
                        ),
                      if (!_addingExcluded)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _addingExcluded = true),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 4),
                            child: Text(
                              '+ Add excluded item',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Active toggle
                      _ToggleRow(
                        label: 'Active',
                        subtitle:
                            'Inactive groups are hidden from customers',
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: AppColors.border))),
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
                        : Text(isEdit ? 'Save Changes' : 'Add Group'),
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

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
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
            value ? Icons.visibility_rounded : Icons.visibility_off_outlined,
            color: value ? AppColors.success : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}
