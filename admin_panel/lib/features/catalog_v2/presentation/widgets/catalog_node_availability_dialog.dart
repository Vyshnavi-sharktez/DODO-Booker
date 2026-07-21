import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../domain/models/catalog_node.dart';

/// Dialog for setting the availability of a catalog node.
///
/// Shows one of three options:
///   • Active — visible and bookable.
///   • Temporarily Unavailable — visible but non-bookable; requires a
///     fully admin-defined customer-facing message (no hardcoded copy).
///   • Disable & Hide — hidden from navigation for the current path
///     (relationship-scoped when parentIdContext != null; node-scoped for roots).
///
/// [fetchCurrentState] is called once on open to load the existing state.
/// [onSave] is called with the chosen status and optional message.
class CatalogNodeAvailabilityDialog extends StatefulWidget {
  const CatalogNodeAvailabilityDialog({
    super.key,
    required this.node,
    required this.parentIdContext,
    required this.fetchCurrentState,
    required this.onSave,
  });

  final CatalogNode node;
  final String? parentIdContext;
  final Future<({String status, String? message})> Function() fetchCurrentState;
  final Future<void> Function(String status, String? message) onSave;

  @override
  State<CatalogNodeAvailabilityDialog> createState() =>
      _CatalogNodeAvailabilityDialogState();
}

class _CatalogNodeAvailabilityDialogState
    extends State<CatalogNodeAvailabilityDialog> {
  String _selectedStatus = 'active';
  final _messageCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

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
      final result = await widget.fetchCurrentState();
      if (mounted) {
        setState(() {
          _selectedStatus = result.status;
          _messageCtrl.text = result.message ?? '';
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
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _selectedStatus,
        _selectedStatus == 'unavailable'
            ? _messageCtrl.text.trim()
            : null,
      );
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
