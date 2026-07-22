import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../service_availability_areas/domain/models/service_availability_area.dart';
import '../../domain/models/catalog_node.dart';

/// Dialog for setting the availability of a catalog node.
///
/// Four mutually exclusive options:
///   • Active                   — visible and bookable.
///   • Temporarily Unavailable  — visible but non-bookable; requires a message.
///   • Hide from catalog        — hidden from this path (or all paths for roots).
///   • Location-wise            — active globally but blocked in specific areas.
///
/// Scoping matches the existing availability system:
///   parentIdContext != null → relationship-scoped (path-specific).
///   parentIdContext == null → node-scoped (all paths).
class CatalogNodeAvailabilityDialog extends StatefulWidget {
  const CatalogNodeAvailabilityDialog({
    super.key,
    required this.node,
    required this.parentIdContext,
    required this.fetchCurrentState,
    required this.onSave,
    required this.fetchAreas,
    required this.fetchLocationRestrictions,
    required this.onSaveLocationRestrictions,
  });

  final CatalogNode node;
  final String? parentIdContext;
  final Future<({String status, String? message})> Function() fetchCurrentState;
  final Future<void> Function(String status, String? message) onSave;

  /// Returns all active service availability areas for the platform.
  final Future<List<ServiceAvailabilityArea>> Function() fetchAreas;

  /// Returns the area IDs that are currently disabled for this node/path.
  final Future<List<String>> Function() fetchLocationRestrictions;

  /// Called when saving location restrictions.
  /// Receives the set of area IDs where the node should be unavailable.
  final Future<void> Function(List<String> disabledAreaIds)
      onSaveLocationRestrictions;

  @override
  State<CatalogNodeAvailabilityDialog> createState() =>
      _CatalogNodeAvailabilityDialogState();
}

class _CatalogNodeAvailabilityDialogState
    extends State<CatalogNodeAvailabilityDialog> {
  // 'active' | 'unavailable' | 'hidden' | 'location_wise'
  String _selectedStatus = 'active';
  final _messageCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  List<ServiceAvailabilityArea> _areas = [];
  Set<String> _disabledAreaIds = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentState() async {
    try {
      final results = await Future.wait([
        widget.fetchCurrentState(),
        widget.fetchAreas(),
        widget.fetchLocationRestrictions(),
      ]);
      final stateResult =
          results[0] as ({String status, String? message});
      final areas = results[1] as List<ServiceAvailabilityArea>;
      final disabledIds = results[2] as List<String>;

      if (mounted) {
        setState(() {
          _areas = areas;
          _disabledAreaIds = disabledIds.toSet();
          // Show location_wise only when status is active and restrictions exist
          if (stateResult.status == 'active' && disabledIds.isNotEmpty) {
            _selectedStatus = 'location_wise';
          } else {
            _selectedStatus = stateResult.status;
            _messageCtrl.text = stateResult.message ?? '';
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedStatus == 'unavailable' &&
        _messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'A customer-facing message is required for Temporarily Unavailable.')),
      );
      return;
    }
    if (_selectedStatus == 'location_wise' && _disabledAreaIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Select at least one area to restrict, or choose Active.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_selectedStatus == 'location_wise') {
        // Ensure the node status is active, then store location restrictions.
        await widget.onSave('active', null);
        await widget
            .onSaveLocationRestrictions(_disabledAreaIds.toList());
      } else {
        // Clear location restrictions when switching to any other option.
        await widget.onSave(
          _selectedStatus,
          _selectedStatus == 'unavailable'
              ? _messageCtrl.text.trim()
              : null,
        );
        await widget.onSaveLocationRestrictions([]);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPathScoped = widget.parentIdContext != null;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(isPathScoped),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildContent(isPathScoped),
              _buildFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isPathScoped) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set Availability — ${widget.node.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPathScoped
                      ? 'Change affects only this node via the current parent path.'
                      : 'No parent path — change is node-scoped (affects all paths).',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                color: Colors.white70, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isPathScoped) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOption(
            value: 'active',
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.success,
            label: 'Active',
            subtitle: 'Visible and bookable for customers.',
          ),
          const SizedBox(height: 10),
          _buildOption(
            value: 'unavailable',
            icon: Icons.pause_circle_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'Temporarily Unavailable',
            subtitle:
                'Visible in catalog but booking is blocked. Your message is shown.',
          ),
          if (_selectedStatus == 'unavailable') ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _messageCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Customer-facing message *',
                hintText:
                    "e.g. This service is temporarily on hold. We'll resume soon.",
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildOption(
            value: 'hidden',
            icon: Icons.visibility_off_outlined,
            iconColor: AppColors.textSecondary,
            label: isPathScoped ? 'Hide from this path' : 'Hide from catalog',
            subtitle: isPathScoped
                ? 'Hidden when accessed via this parent. Visible under other parents.'
                : 'Completely hidden from all catalog paths and navigation.',
          ),
          const SizedBox(height: 10),
          _buildOption(
            value: 'location_wise',
            icon: Icons.location_on_outlined,
            iconColor: const Color(0xFF6366F1),
            label: 'Location-wise Availability',
            subtitle:
                'Active everywhere except the areas you select below.',
          ),
          if (_selectedStatus == 'location_wise') ...[
            const SizedBox(height: 12),
            _buildAreaSelector(),
          ],
        ],
      ),
    );
  }

  Widget _buildAreaSelector() {
    if (_areas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'No service areas configured. Add areas in Settings → Service Areas.',
          style:
              TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              'Unavailable in:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _areas.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 14),
            itemBuilder: (_, i) {
              final area = _areas[i];
              final blocked = _disabledAreaIds.contains(area.id);
              return CheckboxListTile(
                value: blocked,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _disabledAreaIds.add(area.id);
                    } else {
                      _disabledAreaIds.remove(area.id);
                    }
                  });
                },
                title: Text(
                  area.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  area.city,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                activeColor: const Color(0xFF6366F1),
                dense: true,
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildOption({
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
  }) {
    final selected = _selectedStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected ? iconColor : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedStatus,
              onChanged: (v) => setState(() => _selectedStatus = v!),
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed:
                _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
