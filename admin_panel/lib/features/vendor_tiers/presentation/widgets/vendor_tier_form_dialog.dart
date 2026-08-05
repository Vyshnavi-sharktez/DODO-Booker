import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/vendor_tier.dart';

class VendorTierFormDialog extends StatefulWidget {
  final VendorTier? existing;
  final int defaultPriority;
  final Future<void> Function(VendorTier tier) onSave;

  const VendorTierFormDialog({
    super.key,
    this.existing,
    required this.defaultPriority,
    required this.onSave,
  });

  @override
  State<VendorTierFormDialog> createState() => _VendorTierFormDialogState();
}

class _VendorTierFormDialogState extends State<VendorTierFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priorityController;
  late final TextEditingController _colorController;
  late final TextEditingController _minBookingsController;
  late final TextEditingController _minRatingController;
  late final TextEditingController _maxCancellationController;
  late final TextEditingController _minCompletionController;

  late String _selectedColorHex;
  late String _selectedIconKey;
  late bool _isActive;
  bool _saving = false;

  static const List<String> _genericColorPresets = [
    '#4285F4', // Blue
    '#00897B', // Teal
    '#3F51B5', // Indigo
    '#8E24AA', // Purple
    '#D81B60', // Pink
    '#FF5722', // Coral
    '#FFB300', // Amber
    '#4CAF50', // Emerald
    '#607D8B', // Slate
    '#212121', // Charcoal
  ];

  @override
  void initState() {
    super.initState();
    final tier = widget.existing;
    _nameController = TextEditingController(text: tier?.name ?? '');
    _descriptionController = TextEditingController(text: tier?.description ?? '');
    _priorityController = TextEditingController(
      text: (tier?.priority ?? widget.defaultPriority).toString(),
    );
    _selectedColorHex = tier?.badgeColor ?? '#4285F4';
    _colorController = TextEditingController(text: _selectedColorHex);
    _selectedIconKey = tier?.badgeIcon ?? 'workspace_premium';
    _isActive = tier?.isActive ?? true;

    _minBookingsController = TextEditingController(
      text: (tier?.minCompletedBookings ?? 0).toString(),
    );
    _minRatingController = TextEditingController(
      text: (tier?.minRating ?? 0.0).toStringAsFixed(1),
    );
    _maxCancellationController = TextEditingController(
      text: (tier?.maxCancellationRate ?? 100.0).toStringAsFixed(1),
    );
    _minCompletionController = TextEditingController(
      text: (tier?.minCompletionRate ?? 0.0).toStringAsFixed(1),
    );

    _colorController.addListener(() {
      final text = _colorController.text.trim();
      if (text.startsWith('#') && (text.length == 7 || text.length == 9)) {
        setState(() {
          _selectedColorHex = text;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priorityController.dispose();
    _colorController.dispose();
    _minBookingsController.dispose();
    _minRatingController.dispose();
    _maxCancellationController.dispose();
    _minCompletionController.dispose();
    super.dispose();
  }

  Color get _currentColor {
    try {
      final hex = _selectedColorHex.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('0xFF$hex'));
      }
    } catch (_) {}
    return AppColors.primary;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final priorityVal = int.parse(_priorityController.text.trim());
      final minBookingsVal = int.tryParse(_minBookingsController.text.trim()) ?? 0;
      final minRatingVal = double.tryParse(_minRatingController.text.trim()) ?? 0.0;
      final maxCancelVal = double.tryParse(_maxCancellationController.text.trim()) ?? 100.0;
      final minCompleteVal = double.tryParse(_minCompletionController.text.trim()) ?? 0.0;

      final updatedTier = VendorTier(
        id: widget.existing?.id ?? '',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        priority: priorityVal,
        badgeColor: _selectedColorHex,
        badgeIcon: _selectedIconKey,
        isActive: _isActive,
        minCompletedBookings: minBookingsVal,
        minRating: minRatingVal,
        maxCancellationRate: maxCancelVal,
        minCompletionRate: minCompleteVal,
        createdBy: widget.existing?.createdBy,
        updatedBy: widget.existing?.updatedBy,
        createdAt: widget.existing?.createdAt,
      );

      await widget.onSave(updatedTier);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save tier: $e'),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
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
                      color: _currentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      VendorTier.availableIcons[_selectedIconKey] ??
                          Icons.workspace_premium_rounded,
                      color: _currentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Vendor Tier' : 'Create Vendor Tier',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tier Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Tier Name *',
                          hintText: 'e.g. Premier, Platinum, Gold, Tier 1',
                          prefixIcon: Icon(Icons.label_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Tier name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Notes or benefits for this tier',
                          prefixIcon: Icon(Icons.description_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Priority Rank
                      TextFormField(
                        controller: _priorityController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Priority Order *',
                          hintText: '1 = Highest Priority',
                          prefixIcon: Icon(Icons.format_list_numbered_rounded),
                          helperText: 'Rank 1 is evaluated first during tier promotion.',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Priority order is required';
                          }
                          final parsed = int.tryParse(v.trim());
                          if (parsed == null || parsed < 1) {
                            return 'Enter a valid priority number (≥ 1)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Performance Threshold Criteria Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.auto_graph_rounded,
                                    color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Performance Qualification Thresholds',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Vendors must meet ALL thresholds below to qualify for this tier.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _minBookingsController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Min Completed Orders',
                                      hintText: 'e.g. 50',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _minRatingController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Min Avg Rating (0-5)',
                                      hintText: 'e.g. 4.5',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _maxCancellationController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Max Cancellation Rate %',
                                      hintText: 'e.g. 5.0',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _minCompletionController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Min Completion Rate %',
                                      hintText: 'e.g. 90.0',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Badge Color Picker
                      Text(
                        'Badge Color',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),

                      // Color Presets
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _genericColorPresets.map((hex) {
                          final color = Color(
                            int.parse('0xFF${hex.replaceAll('#', '')}'),
                          );
                          final isSelected =
                              _selectedColorHex.toLowerCase() == hex.toLowerCase();

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedColorHex = hex;
                                _colorController.text = hex;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: Colors.black, width: 3)
                                    : Border.all(color: AppColors.border, width: 1),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.4),
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // Custom Hex Input
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _currentColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _colorController,
                              decoration: const InputDecoration(
                                labelText: 'Custom Hex Color',
                                hintText: '#4285F4',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Badge Icon Selector
                      Text(
                        'Badge Icon',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: VendorTier.availableIcons.entries.map((entry) {
                            final isSelected = _selectedIconKey == entry.key;

                            return InkWell(
                              onTap: () => setState(() => _selectedIconKey = entry.key),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _currentColor.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? _currentColor
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  entry.value,
                                  color: isSelected ? _currentColor : AppColors.textSecondary,
                                  size: 24,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Active Status Switch
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: SwitchListTile(
                          value: _isActive,
                          onChanged: (val) => setState(() => _isActive = val),
                          activeTrackColor: AppColors.primary,
                          title: const Text(
                            'Active Status',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _isActive
                                ? 'Tier is active and available for performance evaluation'
                                : 'Tier is disabled',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions Footer
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    label: Text(isEdit ? 'Save Changes' : 'Create Tier'),
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
