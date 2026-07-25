import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/application/providers/catalog_node_providers.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../../service_availability_areas/application/providers/service_availability_areas_providers.dart';
import '../../../service_availability_areas/domain/models/service_availability_area.dart';
import '../../application/providers/location_seo_providers.dart';
import '../../domain/models/catalog_node_seo.dart';
import '../../domain/models/location_node_seo.dart';

/// Tab 3 of the SEO Management page — Phase 4 Location Pages.
///
/// Left panel: list of active service availability areas.
/// Right panel: location SEO configs for the selected area + add/edit forms.
///
/// Admin curates which area × service combinations have SEO pages.
/// The Node.js generator reads these configs at build time.
class LocationPagesTab extends ConsumerStatefulWidget {
  const LocationPagesTab({super.key});

  @override
  ConsumerState<LocationPagesTab> createState() => _LocationPagesTabState();
}

class _LocationPagesTabState extends ConsumerState<LocationPagesTab> {
  ServiceAvailabilityArea? _selectedArea;

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(serviceAvailabilityAreasProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                child: _AreaListPanel(
                  areasAsync: areasAsync,
                  selectedId: _selectedArea?.id,
                  onSelect: (a) => setState(() => _selectedArea = a),
                ),
              ),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(
                child: _selectedArea == null
                    ? const _EmptySelectionPane()
                    : _AreaDetailPanel(
                        key: ValueKey(_selectedArea!.id),
                        area: _selectedArea!,
                      ),
              ),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              height: _selectedArea == null ? double.infinity : 200,
              child: _AreaListPanel(
                areasAsync: areasAsync,
                selectedId: _selectedArea?.id,
                onSelect: (a) => setState(() => _selectedArea = a),
              ),
            ),
            if (_selectedArea != null) ...[
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: _AreaDetailPanel(
                  key: ValueKey(_selectedArea!.id),
                  area: _selectedArea!,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Area list panel ────────────────────────────────────────────────────────────

class _AreaListPanel extends StatelessWidget {
  const _AreaListPanel({
    required this.areasAsync,
    required this.selectedId,
    required this.onSelect,
  });

  final AsyncValue<List<ServiceAvailabilityArea>> areasAsync;
  final String? selectedId;
  final ValueChanged<ServiceAvailabilityArea> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'SERVICE AREAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: areasAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style:
                      const TextStyle(color: AppColors.textSecondary)),
            ),
            data: (areas) {
              if (areas.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No service areas configured.\n'
                      'Add areas in the Service Availability section first.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: areas.length,
                itemBuilder: (_, i) {
                  final area = areas[i];
                  final isSelected = area.id == selectedId;
                  return InkWell(
                    onTap: () => onSelect(area),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  area.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  area.city,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!area.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'off',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Empty selection pane ───────────────────────────────────────────────────────

class _EmptySelectionPane extends StatelessWidget {
  const _EmptySelectionPane();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_outlined, size: 48, color: AppColors.border),
          SizedBox(height: 12),
          Text(
            'Select a service area to manage its SEO pages',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Area detail panel ──────────────────────────────────────────────────────────

class _AreaDetailPanel extends ConsumerWidget {
  const _AreaDetailPanel({super.key, required this.area});
  final ServiceAvailabilityArea area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagesAsync = ref.watch(locationPagesForAreaProvider(area.id));
    final nodesAsync = ref.watch(catalogNodeNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Area header ───────────────────────────────────────────────────────
        _AreaHeader(area: area),
        const Divider(height: 1, color: AppColors.border),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(
          child: pagesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Error loading pages: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (pages) => _AreaPagesList(
              area: area,
              pages: pages,
              nodesAsync: nodesAsync,
              onChanged: () =>
                  ref.invalidate(locationPagesForAreaProvider(area.id)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Area header ────────────────────────────────────────────────────────────────

class _AreaHeader extends StatelessWidget {
  const _AreaHeader({required this.area});
  final ServiceAvailabilityArea area;

  @override
  Widget build(BuildContext context) {
    final slug = area.slug;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${area.name}, ${area.city}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${area.radiusKm} km radius  ·  ${area.isActive ? "Active" : "Inactive"}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (slug != null && slug.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Text(
                        'URL prefix: ',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '/s/location/$slug/',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pages list ─────────────────────────────────────────────────────────────────

class _AreaPagesList extends StatelessWidget {
  const _AreaPagesList({
    required this.area,
    required this.pages,
    required this.nodesAsync,
    required this.onChanged,
  });

  final ServiceAvailabilityArea area;
  final List<LocationNodeSeo> pages;
  final AsyncValue<List<CatalogNode>> nodesAsync;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // ── Add button ───────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              pages.isEmpty
                  ? 'No location pages configured for this area'
                  : '${pages.length} page(s) configured',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            FilledButton.icon(
              onPressed: nodesAsync.hasValue
                  ? () => _openAddDialog(context, nodesAsync.value!)
                  : null,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Service Page'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),

        if (pages.isEmpty) ...[
          const SizedBox(height: 32),
          _EmptyPagesHint(area: area),
        ] else ...[
          const SizedBox(height: 16),
          ...pages.map(
            (p) => _PageTile(
              page: p,
              area: area,
              nodesAsync: nodesAsync,
              onChanged: onChanged,
            ),
          ),
        ],
      ],
    );
  }

  void _openAddDialog(BuildContext context, List<CatalogNode> nodes) {
    showDialog<void>(
      context: context,
      builder: (_) => _LocationPageDialog(
        area: area,
        existingNodeIds: pages.map((p) => p.nodeId).toSet(),
        nodes: nodes,
        onSaved: onChanged,
      ),
    );
  }
}

// ── Empty hint ─────────────────────────────────────────────────────────────────

class _EmptyPagesHint extends StatelessWidget {
  const _EmptyPagesHint({required this.area});
  final ServiceAvailabilityArea area;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.border, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Getting started with Location Pages',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '1. Click "Add Service Page" and pick a bookable catalog service.\n'
            '2. Write a unique SEO Title (include the area name), a location-specific\n'
            '   Meta Description, and editorial body text about this service in\n'
            '   $_placeholder (this is what makes the page unique from the generic page).\n'
            '3. Save — then re-run the SEO generator to publish the page.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }

  // Avoid using non-const area.name in const constructor — use a helper
  static const String _placeholder = 'this area';
}

// ── Single page tile ───────────────────────────────────────────────────────────

class _PageTile extends ConsumerWidget {
  const _PageTile({
    required this.page,
    required this.area,
    required this.nodesAsync,
    required this.onChanged,
  });

  final LocationNodeSeo page;
  final ServiceAvailabilityArea area;
  final AsyncValue<List<CatalogNode>> nodesAsync;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = nodesAsync.valueOrNull ?? [];
    final node =
        nodes.where((n) => n.id == page.nodeId).firstOrNull;
    final health = page.healthStatus;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openEditDialog(context, ref, nodes),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                node?.isBookable == true && node?.childrenCount == 0
                    ? Icons.build_circle_outlined
                    : Icons.folder_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node?.name ?? 'Loading…',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (page.seoTitle != null &&
                        page.seoTitle!.isNotEmpty)
                      Text(
                        page.seoTitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HealthDot(status: health),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditDialog(
      BuildContext context, WidgetRef ref, List<CatalogNode> nodes) {
    showDialog<void>(
      context: context,
      builder: (_) => _LocationPageDialog(
        area: area,
        existingNodeIds: const {},
        nodes: nodes,
        existing: page,
        onSaved: onChanged,
        onDeleted: () {
          ref
              .read(locationSeoRepositoryProvider)
              .delete(page.id)
              .then((_) => onChanged());
        },
      ),
    );
  }
}

// ── Health dot (reuses the same visual pattern as CatalogSeoTab) ───────────────

class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.status});
  final SeoHealthStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case SeoHealthStatus.notConfigured:
        color = AppColors.border;
      case SeoHealthStatus.noindex:
        color = AppColors.warning;
      case SeoHealthStatus.needsAttention:
        color = const Color(0xFFD69E2E);
      case SeoHealthStatus.basicConfigured:
        color = AppColors.accent;
    }
    return Tooltip(
      message: status.label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Add / Edit dialog ──────────────────────────────────────────────────────────

class _LocationPageDialog extends ConsumerStatefulWidget {
  const _LocationPageDialog({
    required this.area,
    required this.existingNodeIds,
    required this.nodes,
    required this.onSaved,
    this.existing,
    this.onDeleted,
  });

  final ServiceAvailabilityArea area;
  final Set<String> existingNodeIds;
  final List<CatalogNode> nodes;
  final LocationNodeSeo? existing;
  final VoidCallback onSaved;
  final VoidCallback? onDeleted;

  @override
  ConsumerState<_LocationPageDialog> createState() =>
      _LocationPageDialogState();
}

class _LocationPageDialogState
    extends ConsumerState<_LocationPageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _seoTitleCtrl = TextEditingController();
  final _seoDescCtrl = TextEditingController();
  final _ogTitleCtrl = TextEditingController();
  final _ogDescCtrl = TextEditingController();
  final _ogImageCtrl = TextEditingController();
  final _seoContentCtrl = TextEditingController();

  CatalogNode? _selectedNode;
  bool _noindex = false;
  bool _saving = false;
  bool _deleting = false;

  static const int _titleMax = 70;
  static const int _descMax = 160;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _seoTitleCtrl.text = e.seoTitle ?? '';
      _seoDescCtrl.text = e.seoDescription ?? '';
      _ogTitleCtrl.text = e.ogTitle ?? '';
      _ogDescCtrl.text = e.ogDescription ?? '';
      _ogImageCtrl.text = e.ogImageUrl ?? '';
      _seoContentCtrl.text = e.seoContent ?? '';
      _noindex = e.noindex;
      _selectedNode = widget.nodes
          .where((n) => n.id == e.nodeId)
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _seoTitleCtrl.dispose();
    _seoDescCtrl.dispose();
    _ogTitleCtrl.dispose();
    _ogDescCtrl.dispose();
    _ogImageCtrl.dispose();
    _seoContentCtrl.dispose();
    super.dispose();
  }

  List<CatalogNode> get _filteredNodes {
    final q = _searchCtrl.text.trim().toLowerCase();
    return widget.nodes.where((n) {
      if (!n.isActive) return false;
      if (_isEdit) return true;
      if (widget.existingNodeIds.contains(n.id)) return false;
      if (q.isEmpty) return true;
      return n.name.toLowerCase().contains(q) ||
          n.slug.toLowerCase().contains(q) ||
          (n.parentName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _save() async {
    if (_selectedNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a catalog service first')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(locationSeoRepositoryProvider).upsert(
            areaId: widget.area.id,
            nodeId: _selectedNode!.id,
            seoTitle: _seoTitleCtrl.text,
            seoDescription: _seoDescCtrl.text,
            ogTitle: _ogTitleCtrl.text,
            ogDescription: _ogDescCtrl.text,
            ogImageUrl: _ogImageCtrl.text,
            seoContent: _seoContentCtrl.text,
            noindex: _noindex,
          );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete location page?'),
        content: Text(
            'Remove SEO config for "${_selectedNode?.name ?? 'this service'}" '
            'in ${widget.area.name}? The page will be excluded from the '
            'next generator run.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      widget.onDeleted?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _DialogHeader(
              area: widget.area,
              isEdit: _isEdit,
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1, color: AppColors.border),

            // Scrollable form body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Node selection ────────────────────────────────────
                      _SectionLabel(
                          label: 'Service', icon: Icons.build_circle_outlined),
                      const SizedBox(height: 8),
                      if (!_isEdit) ...[
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search catalog nodes…',
                            prefixIcon:
                                Icon(Icons.search_rounded, size: 18),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 140,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            itemCount: _filteredNodes.length,
                            itemBuilder: (_, i) {
                              final n = _filteredNodes[i];
                              final sel = n.id == _selectedNode?.id;
                              return InkWell(
                                onTap: () => setState(() => _selectedNode = n),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  color: sel
                                      ? AppColors.accent.withValues(alpha: 0.1)
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n.name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: sel
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: sel
                                                ? AppColors.accent
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (n.parentName != null)
                                        Text(
                                          n.parentName!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.build_circle_outlined,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                _selectedNode?.name ?? 'Unknown node',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_selectedNode != null && widget.area.slug != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Approx. URL: /s/location/${widget.area.slug}/${_selectedNode!.slug}/',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Actual URL includes the full ancestor path — shown in generator output.',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── SEO Metadata ──────────────────────────────────────
                      _SectionLabel(
                          label: 'SEO Metadata',
                          icon: Icons.manage_search_rounded),
                      const SizedBox(height: 10),
                      _charCountField(
                        controller: _seoTitleCtrl,
                        label: 'SEO Title',
                        hint: _selectedNode != null
                            ? '${_selectedNode!.name} in ${widget.area.name}'
                            : 'e.g. 1 BHK Cleaning in Gachibowli',
                        maxLength: _titleMax,
                        helperText: 'Recommended 50–70 characters. Include the area name.',
                      ),
                      const SizedBox(height: 12),
                      _charCountField(
                        controller: _seoDescCtrl,
                        label: 'Meta Description',
                        hint:
                            'Describe this service specifically for ${widget.area.name}…',
                        maxLength: _descMax,
                        maxLines: 3,
                        helperText: 'Recommended 120–160 characters.',
                      ),
                      const SizedBox(height: 20),

                      // ── Editorial content ─────────────────────────────────
                      _SectionLabel(
                          label: 'Area-specific Content',
                          icon: Icons.article_outlined),
                      const SizedBox(height: 4),
                      const Text(
                        'Write unique body content about this service in this area. '
                        'This is what differentiates the page from the generic service page.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _seoContentCtrl,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: 'Editorial Body Content',
                          hintText:
                              'Describe this specific service in ${widget.area.name}, '
                              'mention landmarks, coverage, typical turnaround…',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── OG overrides ──────────────────────────────────────
                      _SectionLabel(
                          label: 'Open Graph (optional)',
                          icon: Icons.share_rounded),
                      const SizedBox(height: 4),
                      const Text(
                        'Leave blank to inherit from SEO Title / Meta Description.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _ogTitleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'OG Title (optional)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _ogDescCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'OG Description (optional)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _ogImageCtrl,
                        decoration: const InputDecoration(
                          labelText: 'OG Image URL (optional)',
                          hintText: 'https://…/image.jpg',
                          isDense: true,
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isNotEmpty && !s.startsWith('http')) {
                            return 'Must be a URL starting with http';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // ── Indexing ──────────────────────────────────────────
                      _SectionLabel(
                          label: 'Indexing', icon: Icons.search_off_rounded),
                      const SizedBox(height: 8),
                      _IndexingToggle(
                        noindex: _noindex,
                        onChanged: (v) => setState(() => _noindex = v),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),

            // Footer actions
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  if (_isEdit && widget.onDeleted != null)
                    TextButton.icon(
                      onPressed: _deleting ? null : _delete,
                      icon: _deleting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.error),
                            )
                          : const Icon(Icons.delete_outline_rounded,
                              size: 16, color: AppColors.error),
                      label: const Text('Delete',
                          style: TextStyle(color: AppColors.error)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _charCountField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    String? helperText,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final len = controller.text.trim().length;
        final over = len > maxLength;
        return TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helperText,
            helperMaxLines: 2,
            counterText: '$len / $maxLength',
            counterStyle: TextStyle(
              fontSize: 11,
              color: over ? AppColors.error : AppColors.textSecondary,
            ),
            isDense: true,
          ),
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          validator: (v) {
            if ((v?.trim().length ?? 0) > maxLength) {
              return '$label exceeds $maxLength characters';
            }
            return null;
          },
        );
      },
    );
  }
}

// ── Dialog header ──────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.area,
    required this.isEdit,
    required this.onClose,
  });

  final ServiceAvailabilityArea area;
  final bool isEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit
                      ? 'Edit Location SEO Page'
                      : 'Add Location SEO Page',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${area.name}, ${area.city}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onClose,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

// ── Indexing toggle ────────────────────────────────────────────────────────────

class _IndexingToggle extends StatelessWidget {
  const _IndexingToggle({required this.noindex, required this.onChanged});
  final bool noindex;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _IndexOption(
            label: 'Index',
            icon: Icons.search_rounded,
            iconColor: AppColors.success,
            selected: !noindex,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _IndexOption(
            label: 'Noindex',
            icon: Icons.search_off_rounded,
            iconColor: AppColors.warning,
            selected: noindex,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _IndexOption extends StatelessWidget {
  const _IndexOption({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? iconColor.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? iconColor : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Form section label ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}
