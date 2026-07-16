import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/serving_areas_provider.dart';
import '../../domain/models/serving_area.dart';

/// Displays the list of active serving areas with checkboxes.
///
/// Selection state is owned by the caller via [selected] / [onToggle].
/// There is no internal Save button — the parent persists on its own save.
class ServingAreasSelector extends ConsumerStatefulWidget {
  const ServingAreasSelector({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final void Function(String id) onToggle;

  @override
  ConsumerState<ServingAreasSelector> createState() =>
      _ServingAreasSelectorState();
}

class _ServingAreasSelectorState extends ConsumerState<ServingAreasSelector> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(activeServingAreasProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.location_on_rounded,
                    size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Serving Areas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Select the zones where you provide services',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 0, color: AppColors.border),

          areasAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load serving areas: $e',
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
            data: (areas) {
              if (areas.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No serving areas available yet. Please contact the admin.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                );
              }

              final filtered = _search.isEmpty
                  ? areas
                  : areas
                      .where((a) =>
                          a.name
                              .toLowerCase()
                              .contains(_search.toLowerCase()) ||
                          a.city
                              .toLowerCase()
                              .contains(_search.toLowerCase()))
                      .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: TextFormField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Search areas…',
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 18),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.background,
                      ),
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final area = filtered[i];
                      final checked = widget.selected.contains(area.id);
                      return _AreaTile(
                        area: area,
                        checked: checked,
                        onToggle: () => widget.onToggle(area.id),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.area,
    required this.checked,
    required this.onToggle,
  });
  final ServingArea area;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: AppColors.primary,
              onChanged: (_) => onToggle(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${area.city}  •  ${area.radiusKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (checked)
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
