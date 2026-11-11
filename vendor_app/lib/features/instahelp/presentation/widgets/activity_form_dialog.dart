import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/instahelp_activity.dart';

class VendorActivityFormDialog extends StatefulWidget {
  final InstaHelpActivity? existing;
  final Future<void> Function({
    required String title,
    required List<String> includedItems,
    required List<String> excludedItems,
    required bool isActive,
  }) onSave;

  const VendorActivityFormDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<VendorActivityFormDialog> createState() => _VendorActivityFormDialogState();
}

class _VendorActivityFormDialogState extends State<VendorActivityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late List<String> _includedItems;
  late List<String> _excludedItems;
  late final TextEditingController _newIncludedCtrl;
  late final TextEditingController _newExcludedCtrl;
  bool _addingIncluded = false;
  bool _addingExcluded = false;
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

  Widget _itemRow(String text, {required VoidCallback onRemove, required void Function(String) onEdit}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Icon(Icons.drag_indicator_rounded, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        GestureDetector(
          onTap: () async {
            final ctrl = TextEditingController(text: text);
            final updated = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: const Text('Edit item', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () {
                      final v = ctrl.text.trim();
                      Navigator.of(ctx).pop(v.isEmpty ? null : v);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            ctrl.dispose();
            if (updated != null) onEdit(updated);
          },
          child: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(Icons.close_rounded, size: 16, color: AppColors.error),
        ),
      ]),
    );
  }

  Widget _inlineInput({
    required TextEditingController ctrl,
    required VoidCallback onAdd,
    required VoidCallback onCancel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter item...',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onAdd, child: const Text('Add')),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ]),
    );
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
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.layers_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(isEdit ? 'Edit Activity Group' : 'Add Activity Group',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(labelText: 'Activity Title *', hintText: 'e.g. Kitchen'),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Included
                      Row(children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.success),
                        const SizedBox(width: 6),
                        const Text('Included Items', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
                      ]),
                      const SizedBox(height: 8),
                      ..._includedItems.asMap().entries.map((e) => _itemRow(e.value,
                        onRemove: () => setState(() => _includedItems.removeAt(e.key)),
                        onEdit: (v) => setState(() => _includedItems[e.key] = v),
                      )),
                      if (_includedItems.isEmpty && !_addingIncluded)
                        Padding(padding: const EdgeInsets.only(bottom: 6),
                            child: Text('No items yet.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      if (_addingIncluded)
                        _inlineInput(
                          ctrl: _newIncludedCtrl,
                          onAdd: () {
                            final v = _newIncludedCtrl.text.trim();
                            if (v.isNotEmpty) setState(() { _includedItems.add(v); _newIncludedCtrl.clear(); _addingIncluded = false; });
                          },
                          onCancel: () => setState(() { _newIncludedCtrl.clear(); _addingIncluded = false; }),
                        ),
                      if (!_addingIncluded)
                        GestureDetector(
                          onTap: () => setState(() => _addingIncluded = true),
                          child: Padding(padding: const EdgeInsets.only(top: 2, bottom: 4),
                              child: Text('+ Add included item', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w500))),
                        ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Excluded
                      Row(children: [
                        const Icon(Icons.do_not_disturb_alt_rounded, size: 14, color: AppColors.error),
                        const SizedBox(width: 6),
                        const Text('Excluded Items', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error)),
                      ]),
                      const SizedBox(height: 8),
                      ..._excludedItems.asMap().entries.map((e) => _itemRow(e.value,
                        onRemove: () => setState(() => _excludedItems.removeAt(e.key)),
                        onEdit: (v) => setState(() => _excludedItems[e.key] = v),
                      )),
                      if (_excludedItems.isEmpty && !_addingExcluded)
                        Padding(padding: const EdgeInsets.only(bottom: 6),
                            child: Text('No items yet.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      if (_addingExcluded)
                        _inlineInput(
                          ctrl: _newExcludedCtrl,
                          onAdd: () {
                            final v = _newExcludedCtrl.text.trim();
                            if (v.isNotEmpty) setState(() { _excludedItems.add(v); _newExcludedCtrl.clear(); _addingExcluded = false; });
                          },
                          onCancel: () => setState(() { _newExcludedCtrl.clear(); _addingExcluded = false; }),
                        ),
                      if (!_addingExcluded)
                        GestureDetector(
                          onTap: () => setState(() => _addingExcluded = true),
                          child: Padding(padding: const EdgeInsets.only(top: 2, bottom: 4),
                              child: Text('+ Add excluded item', style: TextStyle(fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w500))),
                        ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        subtitle: Text('Inactive groups are hidden from customers',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: AppColors.success,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
