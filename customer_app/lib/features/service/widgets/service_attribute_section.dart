import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_attribute_model.dart';

/// Renders all selectable attributes for a service with option chips that
/// display `+₹XX` price adjustments. Fires [onChanged] whenever a selection
/// changes so the parent can recalculate the live price.
class ServiceAttributeSection extends StatelessWidget {
  final List<ServiceAttributeModel> attrs;
  final Map<String, String> selections;
  final void Function(String attrId, String optId) onChanged;

  const ServiceAttributeSection({
    super.key,
    required this.attrs,
    required this.selections,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectableAttrs = attrs.where((a) => a.hasOptions).toList();
    if (selectableAttrs.isEmpty) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attr in selectableAttrs) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Row(
              children: [
                Text(
                  attr.name,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (attr.isRequired) ...[
                  const SizedBox(width: 3),
                  const Text(
                    '*',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attr.options.map((opt) {
                final selected = selections[attr.id] == opt.id;
                final adjLabel = opt.priceAdjustment > 0
                    ? ' (+₹${opt.priceAdjustment.toStringAsFixed(0)})'
                    : '';
                return _AttrChip(
                  label: '${opt.optionName}$adjLabel',
                  selected: selected,
                  onTap: () => onChanged(attr.id, opt.id),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _AttrChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AttrChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
