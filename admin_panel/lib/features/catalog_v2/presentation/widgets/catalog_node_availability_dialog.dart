import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../service_availability_areas/domain/models/service_availability_area.dart';
import '../../domain/models/catalog_node.dart';

/// Dialog for setting the availability of a catalog node.
///
/// For ROOT nodes (parentIdContext == null) the dialog shows a single set of
/// four options that write to catalog_nodes.availability_status.
///
/// For CHILD nodes (parentIdContext != null) the dialog shows TWO sections:
///   • Global Availability — writes catalog_nodes.availability_status (node-level,
///     affects all catalog paths this node appears under).
///   • Category Availability — writes catalog_node_relationships.availability_status
///     (path-specific, affects only this parent→child path).
///
/// This ensures an admin can see and fix a node-level "hidden" status that would
/// otherwise be invisible when the node is rendered under a parent.
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
    this.nodeAvailabilityStatus = 'active',
    this.nodeUnavailabilityMessage,
    this.onSaveGlobal,
  });

  final CatalogNode node;
  final String? parentIdContext;

  /// Returns the current CATEGORY-level status for child nodes, or the
  /// node-level status for root nodes.
  final Future<({String status, String? message})> Function() fetchCurrentState;

  /// Saves the category-level (or node-level for roots) status.
  final Future<void> Function(String status, String? message) onSave;

  final Future<List<ServiceAvailabilityArea>> Function() fetchAreas;

  final Future<List<String>> Function() fetchLocationRestrictions;

  final Future<void> Function(List<String> disabledAreaIds)
      onSaveLocationRestrictions;

  /// Current catalog_nodes.availability_status (global node-level).
  /// Passed for child nodes so the global section can be pre-populated
  /// without an extra fetch.
  final String nodeAvailabilityStatus;

  /// Current catalog_nodes.unavailability_message (global node-level).
  final String? nodeUnavailabilityMessage;

  /// Saves the global (node-level) availability status.
  /// Non-null only for child nodes — root nodes already use [onSave] for this.
  final Future<void> Function(String status, String? message)? onSaveGlobal;

  @override
  State<CatalogNodeAvailabilityDialog> createState() =>
      _CatalogNodeAvailabilityDialogState();
}

class _CatalogNodeAvailabilityDialogState
    extends State<CatalogNodeAvailabilityDialog> {
  // ── Category-level state (relationship for child nodes, node for root nodes)
  String _selectedStatus = 'active';
  final _messageCtrl = TextEditingController();

  // ── Global (node-level) state — only used for child nodes
  String _selectedGlobalStatus = 'active';
  String _originalGlobalStatus = 'active';
  final _globalMessageCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  List<ServiceAvailabilityArea> _areas = [];
  Set<String> _disabledAreaIds = {};

  bool get _isPathScoped => widget.parentIdContext != null;

  @override
  void initState() {
    super.initState();
    // Pre-populate global state from passed params (no extra fetch needed).
    _selectedGlobalStatus = widget.nodeAvailabilityStatus;
    _originalGlobalStatus = widget.nodeAvailabilityStatus;
    _globalMessageCtrl.text = widget.nodeUnavailabilityMessage ?? '';
    _loadCurrentState();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _globalMessageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentState() async {
    try {
      final results = await Future.wait([
        widget.fetchCurrentState(),
        widget.fetchAreas(),
        widget.fetchLocationRestrictions(),
      ]);
      final stateResult = results[0] as ({String status, String? message});
      final areas = results[1] as List<ServiceAvailabilityArea>;
      final disabledIds = results[2] as List<String>;

      if (mounted) {
        setState(() {
          _areas = areas;
          _disabledAreaIds = disabledIds.toSet();
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
    // ── Validate category section
    if (_selectedStatus == 'unavailable' && _messageCtrl.text.trim().isEmpty) {
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

    // ── Validate global section (child nodes only)
    if (_isPathScoped &&
        _selectedGlobalStatus == 'unavailable' &&
        _globalMessageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'A customer-facing message is required for Globally Unavailable.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // ── Save global (node-level) if changed — child nodes only
      if (_isPathScoped &&
          widget.onSaveGlobal != null &&
          _selectedGlobalStatus != _originalGlobalStatus) {
        await widget.onSaveGlobal!(
          _selectedGlobalStatus,
          _selectedGlobalStatus == 'unavailable'
              ? _globalMessageCtrl.text.trim()
              : null,
        );
      }

      // ── Save category (relationship-level or node-level for roots)
      if (_selectedStatus == 'location_wise') {
        await widget.onSave('active', null);
        await widget.onSaveLocationRestrictions(_disabledAreaIds.toList());
      } else {
        await widget.onSave(
          _selectedStatus,
          _selectedStatus == 'unavailable' ? _messageCtrl.text.trim() : null,
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
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Flexible(
                child: SingleChildScrollView(
                  child: _isPathScoped
                      ? _buildChildContent()
                      : _buildRootContent(),
                ),
              ),
              _buildFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                  _isPathScoped
                      ? 'Manage global and category-specific availability.'
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

  // ── Child node content: two sections ─────────────────────────────────────────

  Widget _buildChildContent() {
    final globalNonActive = _selectedGlobalStatus != 'active';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Global Availability section ─────────────────────────────────────
          _buildSectionHeader(
            icon: Icons.public_rounded,
            label: 'Global Availability',
            subtitle: 'Applies to all catalog paths regardless of category.',
            isWarning: globalNonActive,
          ),
          const SizedBox(height: 10),
          _buildOption(
            value: 'active',
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.success,
            label: 'Active',
            subtitle: 'Visible via all catalog paths.',
            isGlobal: true,
          ),
          const SizedBox(height: 8),
          _buildOption(
            value: 'unavailable',
            icon: Icons.pause_circle_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'Globally Unavailable',
            subtitle: 'Visible in catalog but not bookable from any path.',
            isGlobal: true,
          ),
          if (_selectedGlobalStatus == 'unavailable') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _globalMessageCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Customer-facing message *',
                hintText: 'e.g. Service temporarily on hold.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _buildOption(
            value: 'hidden',
            icon: Icons.visibility_off_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Globally Hidden',
            subtitle: 'Hidden from all catalog paths. Category status has no effect.',
            isGlobal: true,
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // ── Category Availability section ───────────────────────────────────
          _buildSectionHeader(
            icon: Icons.folder_outlined,
            label: 'Category Availability',
            subtitle: 'Applies only to this parent → child path.',
            isWarning: false,
          ),
          const SizedBox(height: 10),
          _buildOption(
            value: 'active',
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.success,
            label: 'Active',
            subtitle: 'Visible and bookable via this category.',
            isGlobal: false,
          ),
          const SizedBox(height: 8),
          _buildOption(
            value: 'unavailable',
            icon: Icons.pause_circle_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'Temporarily Unavailable',
            subtitle:
                'Visible in this category but booking is blocked. Your message is shown.',
            isGlobal: false,
          ),
          if (_selectedStatus == 'unavailable') ...[
            const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          _buildOption(
            value: 'hidden',
            icon: Icons.visibility_off_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Hide from this category',
            subtitle:
                'Hidden via this path. Visible under other categories.',
            isGlobal: false,
          ),
          const SizedBox(height: 8),
          _buildOption(
            value: 'location_wise',
            icon: Icons.location_on_outlined,
            iconColor: const Color(0xFF6366F1),
            label: 'Location-wise Availability',
            subtitle: 'Active except in the areas you select below.',
            isGlobal: false,
          ),
          if (_selectedStatus == 'location_wise') ...[
            const SizedBox(height: 12),
            _buildAreaSelector(),
          ],
        ],
      ),
    );
  }

  // ── Root node content: original single-section layout ────────────────────────

  Widget _buildRootContent() {
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
            isGlobal: false,
          ),
          const SizedBox(height: 10),
          _buildOption(
            value: 'unavailable',
            icon: Icons.pause_circle_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'Temporarily Unavailable',
            subtitle:
                'Visible in catalog but booking is blocked. Your message is shown.',
            isGlobal: false,
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
            label: 'Hide from catalog',
            subtitle:
                'Completely hidden from all catalog paths and navigation.',
            isGlobal: false,
          ),
          const SizedBox(height: 10),
          _buildOption(
            value: 'location_wise',
            icon: Icons.location_on_outlined,
            iconColor: const Color(0xFF6366F1),
            label: 'Location-wise Availability',
            subtitle:
                'Active everywhere except the areas you select below.',
            isGlobal: false,
          ),
          if (_selectedStatus == 'location_wise') ...[
            const SizedBox(height: 12),
            _buildAreaSelector(),
          ],
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isWarning,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isWarning
            ? const Color(0xFFFFF8E1)
            : AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWarning
              ? const Color(0xFFFFE082)
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : icon,
            size: 15,
            color: isWarning
                ? const Color(0xFFF9A825)
                : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isWarning
                        ? const Color(0xFF795548)
                        : AppColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3),
                ),
              ],
            ),
          ),
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
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
            separatorBuilder: (context, index) =>
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

  /// Builds a single selectable option card.
  ///
  /// [isGlobal] routes taps and the radio groupValue to the global section
  /// state ([_selectedGlobalStatus]) vs the category section state
  /// ([_selectedStatus]).
  Widget _buildOption({
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required bool isGlobal,
  }) {
    final groupValue = isGlobal ? _selectedGlobalStatus : _selectedStatus;
    final selected = groupValue == value;
    return GestureDetector(
      onTap: () => setState(() {
        if (isGlobal) {
          _selectedGlobalStatus = value;
        } else {
          _selectedStatus = value;
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
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
              groupValue: groupValue,
              onChanged: (v) => setState(() {
                if (isGlobal) {
                  _selectedGlobalStatus = v!;
                } else {
                  _selectedStatus = v!;
                }
              }),
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
