import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/application/providers/catalog_node_providers.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../application/providers/seo_providers.dart';
import '../../domain/models/catalog_node_seo.dart';
import '../../domain/models/seo_global_settings.dart';

/// Tab 2 of the SEO Management page.
///
/// Left panel: searchable flat list of all catalog nodes with SEO health overlay.
/// Right panel: SEO configuration form for the selected node.
///
/// The catalog node list reuses the existing [catalogNodeNotifierProvider].
/// No catalog data is duplicated or fetched separately.
class CatalogSeoTab extends ConsumerStatefulWidget {
  const CatalogSeoTab({super.key});

  @override
  ConsumerState<CatalogSeoTab> createState() => _CatalogSeoTabState();
}

class _CatalogSeoTabState extends ConsumerState<CatalogSeoTab> {
  final _searchCtrl = TextEditingController();
  CatalogNode? _selectedNode;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CatalogNode> _filtered(List<CatalogNode> nodes) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return nodes;
    return nodes.where((n) {
      return n.name.toLowerCase().contains(q) ||
          (n.parentName?.toLowerCase().contains(q) ?? false) ||
          n.slug.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(catalogNodeNotifierProvider);
    final seoMapAsync = ref.watch(allNodeSeoMapProvider);
    final globalAsync = ref.watch(seoGlobalSettingsProvider);

    final seoMap = seoMapAsync.valueOrNull ?? {};
    final globalSettings = globalAsync.valueOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: node list
              SizedBox(
                width: 300,
                child: _NodeListPanel(
                  nodesAsync: nodesAsync,
                  seoMap: seoMap,
                  searchCtrl: _searchCtrl,
                  selectedId: _selectedNode?.id,
                  filtered: (nodes) => _filtered(nodes),
                  onSelect: (node) => setState(() => _selectedNode = node),
                  onSearchChanged: () => setState(() {}),
                ),
              ),
              const VerticalDivider(width: 1, color: AppColors.border),
              // Right: form
              Expanded(
                child: _selectedNode == null
                    ? const _EmptySelectionPane()
                    : _NodeSeoForm(
                        key: ValueKey(_selectedNode!.id),
                        node: _selectedNode!,
                        globalSettings: globalSettings,
                        onSaved: () => ref.invalidate(allNodeSeoMapProvider),
                      ),
              ),
            ],
          );
        }

        // Narrow: list stacked above form
        return Column(
          children: [
            SizedBox(
              height: _selectedNode == null ? double.infinity : 220,
              child: _NodeListPanel(
                nodesAsync: nodesAsync,
                seoMap: seoMap,
                searchCtrl: _searchCtrl,
                selectedId: _selectedNode?.id,
                filtered: (nodes) => _filtered(nodes),
                onSelect: (node) => setState(() => _selectedNode = node),
                onSearchChanged: () => setState(() {}),
              ),
            ),
            if (_selectedNode != null) ...[
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: _NodeSeoForm(
                  key: ValueKey(_selectedNode!.id),
                  node: _selectedNode!,
                  globalSettings: globalSettings,
                  onSaved: () => ref.invalidate(allNodeSeoMapProvider),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Node list panel ────────────────────────────────────────────────────────────

class _NodeListPanel extends StatelessWidget {
  const _NodeListPanel({
    required this.nodesAsync,
    required this.seoMap,
    required this.searchCtrl,
    required this.selectedId,
    required this.filtered,
    required this.onSelect,
    required this.onSearchChanged,
  });

  final AsyncValue<List<CatalogNode>> nodesAsync;
  final Map<String, CatalogNodeSeo> seoMap;
  final TextEditingController searchCtrl;
  final String? selectedId;
  final List<CatalogNode> Function(List<CatalogNode>) filtered;
  final ValueChanged<CatalogNode> onSelect;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: searchCtrl,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              hintText: 'Search catalog nodes…',
              prefixIcon:
                  const Icon(Icons.search_rounded, size: 18),
              suffixIcon: searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        searchCtrl.clear();
                        onSearchChanged();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        // Node list
        Expanded(
          child: nodesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Error loading catalog: $e',
                style:
                    const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            data: (nodes) {
              final items = filtered(nodes);
              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'No nodes match your search',
                    style:
                        TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final node = items[i];
                  final seo = seoMap[node.id];
                  return _NodeListTile(
                    node: node,
                    seo: seo,
                    isSelected: node.id == selectedId,
                    onTap: () => onSelect(node),
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

// ── Single node list tile ──────────────────────────────────────────────────────

class _NodeListTile extends StatelessWidget {
  const _NodeListTile({
    required this.node,
    required this.seo,
    required this.isSelected,
    required this.onTap,
  });

  final CatalogNode node;
  final CatalogNodeSeo? seo;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final health =
        seo?.healthStatus ?? SeoHealthStatus.notConfigured;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Node type icon
            Icon(
              node.isBookable && node.childrenCount == 0
                  ? Icons.build_circle_outlined
                  : Icons.folder_outlined,
              size: 16,
              color: isSelected
                  ? AppColors.accent
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            // Name + parent
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
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
                  if (node.parentName != null)
                    Text(
                      node.parentName!,
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
            const SizedBox(width: 6),
            // SEO health dot
            _HealthDot(status: health),
          ],
        ),
      ),
    );
  }
}

// ── Health dot indicator ───────────────────────────────────────────────────────

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
        color = const Color(0xFFD69E2E); // amber
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

// ── Empty selection pane ───────────────────────────────────────────────────────

class _EmptySelectionPane extends StatelessWidget {
  const _EmptySelectionPane();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined,
              size: 48, color: AppColors.border),
          SizedBox(height: 12),
          Text(
            'Select a catalog node to configure its SEO',
            style:
                TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Node SEO form ──────────────────────────────────────────────────────────────

/// SEO configuration form for a single catalog node.
///
/// Keyed on node.id so Flutter remounts this widget whenever the selected
/// node changes, triggering a fresh load without [didUpdateWidget] logic.
class _NodeSeoForm extends ConsumerStatefulWidget {
  const _NodeSeoForm({
    super.key,
    required this.node,
    required this.globalSettings,
    required this.onSaved,
  });

  final CatalogNode node;
  final SeoGlobalSettings? globalSettings;
  final VoidCallback onSaved;

  @override
  ConsumerState<_NodeSeoForm> createState() => _NodeSeoFormState();
}

class _NodeSeoFormState extends ConsumerState<_NodeSeoForm> {
  final _formKey = GlobalKey<FormState>();

  final _seoTitleCtrl = TextEditingController();
  final _seoDescCtrl = TextEditingController();
  final _ogTitleCtrl = TextEditingController();
  final _ogDescCtrl = TextEditingController();
  final _ogImageCtrl = TextEditingController();
  final _seoContentCtrl = TextEditingController();
  final _primaryTopicCtrl = TextEditingController();

  bool _noindex = false;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  static const int _titleMax = 60;
  static const int _descMax = 160;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _seoTitleCtrl.dispose();
    _seoDescCtrl.dispose();
    _ogTitleCtrl.dispose();
    _ogDescCtrl.dispose();
    _ogImageCtrl.dispose();
    _seoContentCtrl.dispose();
    _primaryTopicCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final seo = await ref
          .read(seoRepositoryProvider)
          .fetchNodeSeo(widget.node.id);
      if (!mounted) return;
      if (seo != null) {
        _seoTitleCtrl.text = seo.seoTitle ?? '';
        _seoDescCtrl.text = seo.seoDescription ?? '';
        _ogTitleCtrl.text = seo.ogTitle ?? '';
        _ogDescCtrl.text = seo.ogDescription ?? '';
        _ogImageCtrl.text = seo.ogImageUrl ?? '';
        _seoContentCtrl.text = seo.seoContent ?? '';
        _primaryTopicCtrl.text = seo.primarySearchTopic ?? '';
        _noindex = seo.noindex;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(seoRepositoryProvider).upsertNodeSeo(
            nodeId: widget.node.id,
            seoTitle: _seoTitleCtrl.text,
            seoDescription: _seoDescCtrl.text,
            ogTitle: _ogTitleCtrl.text,
            ogDescription: _ogDescCtrl.text,
            ogImageUrl: _ogImageCtrl.text,
            seoContent: _seoContentCtrl.text,
            primarySearchTopic: _primaryTopicCtrl.text,
            noindex: _noindex,
          );
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'SEO settings saved for "${widget.node.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 36, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_loadError!,
                style:
                    const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Node info header ─────────────────────────────────────────────
            _NodeInfoHeader(node: widget.node),
            const SizedBox(height: 20),

            // ── SEO Metadata ─────────────────────────────────────────────────
            _FormSectionLabel(
              label: 'SEO Metadata',
              icon: Icons.manage_search_rounded,
            ),
            const SizedBox(height: 12),
            _buildCharCountField(
              controller: _seoTitleCtrl,
              label: 'SEO Title',
              hint: widget.node.name,
              maxLength: _titleMax,
              helperText: 'Recommended 50–60 characters',
            ),
            const SizedBox(height: 14),
            _buildCharCountField(
              controller: _seoDescCtrl,
              label: 'Meta Description',
              hint: widget.node.description ??
                  'Describe this service for search results',
              maxLength: _descMax,
              maxLines: 3,
              helperText: 'Recommended 120–160 characters',
            ),
            const SizedBox(height: 20),

            // ── Open Graph / Social ──────────────────────────────────────────
            _FormSectionLabel(
              label: 'Open Graph / Social',
              icon: Icons.share_rounded,
            ),
            const SizedBox(height: 4),
            const Text(
              'Leave blank to inherit from SEO Title / Meta Description above.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ogTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'OG Title (optional override)',
                hintText: 'Leave blank to use SEO Title',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ogDescCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'OG Description (optional override)',
                hintText: 'Leave blank to use Meta Description',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ogImageCtrl,
              decoration: const InputDecoration(
                labelText: 'OG Image URL (optional)',
                hintText: 'https://…/image.jpg',
                prefixIcon: Icon(Icons.image_outlined, size: 18),
                helperText: 'Overrides the global default OG image',
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isNotEmpty && !s.startsWith('http')) {
                  return 'Must be a valid URL starting with http';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── Editorial Content ────────────────────────────────────────────
            _FormSectionLabel(
              label: 'Editorial Content',
              icon: Icons.article_outlined,
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional body content for the future SEO page. '
              'Supports plain text or markdown.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _seoContentCtrl,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'SEO / Editorial Body Content',
                hintText:
                    'Describe this service in depth for potential customers…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            // ── Primary Search Topic ─────────────────────────────────────────
            _FormSectionLabel(
              label: 'Search Strategy',
              icon: Icons.track_changes_rounded,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _primaryTopicCtrl,
              decoration: const InputDecoration(
                labelText: 'Primary Search Topic',
                hintText: 'e.g. deep bathroom cleaning',
                helperText:
                    'Editorial guidance only — records the search intent '
                    'this page targets. Not stored as keywords and not '
                    'automatically injected anywhere.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 20),

            // ── Indexing ─────────────────────────────────────────────────────
            _FormSectionLabel(
              label: 'Indexing',
              icon: Icons.search_off_rounded,
            ),
            const SizedBox(height: 8),
            _IndexingControl(
              noindex: _noindex,
              onChanged: (v) => setState(() => _noindex = v),
            ),
            const SizedBox(height: 24),

            // ── SERP Preview ─────────────────────────────────────────────────
            _FormSectionLabel(
              label: 'SERP Preview',
              icon: Icons.preview_rounded,
            ),
            const SizedBox(height: 4),
            const Text(
              'Approximate preview only — actual appearance depends on '
              'Google\'s algorithms and content quality.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: Listenable.merge(
                  [_seoTitleCtrl, _seoDescCtrl]),
              builder: (_, _) => _SerpPreview(
                node: widget.node,
                seoTitle: _seoTitleCtrl.text.trim(),
                seoDescription: _seoDescCtrl.text.trim(),
                noindex: _noindex,
                domain: widget.globalSettings?.productionDomain,
              ),
            ),
            const SizedBox(height: 28),

            // ── Actions ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                      _saving ? 'Saving…' : 'Save SEO Settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF805AD5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Field helpers ──────────────────────────────────────────────────────────

  Widget _buildCharCountField({
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
            counterText: '$len / $maxLength',
            counterStyle: TextStyle(
              fontSize: 11,
              color: over ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
              null,
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

// ── Node info header ───────────────────────────────────────────────────────────

class _NodeInfoHeader extends StatelessWidget {
  const _NodeInfoHeader({required this.node});
  final CatalogNode node;

  String get _nodeTypeLabel {
    if (node.childrenCount > 0) {
      return node.isRoot ? 'Root Category' : 'Subcategory';
    }
    return node.isBookable ? 'Service' : 'Leaf Node';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            node.isBookable && node.childrenCount == 0
                ? Icons.build_circle_outlined
                : Icons.folder_outlined,
            size: 22,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(label: _nodeTypeLabel),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Slug: ',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
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
                        node.slug,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (node.parentName != null) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'under ',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        node.parentName!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'The catalog slug is read-only here. '
                  'Slug changes and redirect management will be available in a future phase.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Form section label ─────────────────────────────────────────────────────────

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
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

// ── Indexing control ───────────────────────────────────────────────────────────

class _IndexingControl extends StatelessWidget {
  const _IndexingControl({
    required this.noindex,
    required this.onChanged,
  });

  final bool noindex;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: noindex
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          _IndexOption(
            label: 'Index',
            description:
                'This node may be included in the sitemap and SEO pages.',
            icon: Icons.search_rounded,
            iconColor: AppColors.success,
            selected: !noindex,
            onTap: () => onChanged(false),
          ),
          const SizedBox(height: 8),
          _IndexOption(
            label: 'Noindex',
            description:
                'This node will be excluded from the sitemap and '
                'any generated SEO page will carry a noindex directive.',
            icon: Icons.search_off_rounded,
            iconColor: AppColors.warning,
            selected: noindex,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _IndexOption extends StatelessWidget {
  const _IndexOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? iconColor : AppColors.border, width: 2),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: iconColor,
                        ),
                      ),
                    )
                  : null,
            ),
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
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

// ── SERP preview ───────────────────────────────────────────────────────────────

class _SerpPreview extends StatelessWidget {
  const _SerpPreview({
    required this.node,
    required this.seoTitle,
    required this.seoDescription,
    required this.noindex,
    required this.domain,
  });

  final CatalogNode node;
  final String seoTitle;
  final String seoDescription;
  final bool noindex;
  final String? domain;

  String get _displayDomain {
    if (domain != null && domain!.isNotEmpty) {
      return domain!
          .replaceFirst('https://', '')
          .replaceFirst('http://', '');
    }
    return 'yourdomain.com';
  }

  String get _displayPath {
    final parent = node.parentSlug;
    final slug = node.slug;
    if (parent != null && parent.isNotEmpty) {
      return '/s/$parent/$slug/';
    }
    return '/s/$slug/';
  }

  String get _displayTitle {
    if (seoTitle.isNotEmpty) return seoTitle;
    return node.name;
  }

  String get _displayDescription {
    if (seoDescription.isNotEmpty) return seoDescription;
    if (node.description != null && node.description!.isNotEmpty) {
      return node.description!;
    }
    return 'No description configured yet.';
  }

  @override
  Widget build(BuildContext context) {
    if (noindex) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_off_rounded,
                size: 20, color: AppColors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Noindex — this node will not be included in the sitemap '
                'or any generated SEO page.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.warning),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL line
          Text(
            '$_displayDomain$_displayPath',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF0D652D),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Title
          Text(
            _displayTitle.length > 70
                ? '${_displayTitle.substring(0, 67)}…'
                : _displayTitle,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF1A0DAB),
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Description
          Text(
            _displayDescription.length > 180
                ? '${_displayDescription.substring(0, 177)}…'
                : _displayDescription,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4D5156),
              height: 1.4,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
