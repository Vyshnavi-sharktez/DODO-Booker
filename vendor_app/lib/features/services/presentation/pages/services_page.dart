import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../customer_questions/domain/models/customer_question_model.dart';
import '../../../customer_questions/presentation/providers/customer_questions_provider.dart';
import '../../domain/models/assigned_service.dart';
import '../../domain/models/catalog_service.dart';
import '../../domain/models/vendor_service_request_model.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../providers/services_provider.dart';
import '../widgets/service_card.dart';
import '../widgets/vendor_search_bar.dart';
import '../widgets/vendor_service_config_dialog.dart';

// ── Category palette — assigned by root-category sort index ───────────────────
const _kCatColors = [
  Color(0xFF4A90D9),
  Color(0xFFE67E22),
  Color(0xFF27AE60),
  Color(0xFF8E44AD),
  Color(0xFFE74C3C),
  Color(0xFF16A085),
  Color(0xFFF39C12),
  Color(0xFF2980B9),
  Color(0xFFC0392B),
  Color(0xFF1ABC9C),
];

const _kPreview = 4; // service rows shown before "View all X services →"

IconData _iconForCategory(String name) {
  final n = name.toLowerCase();
  if (n.contains('clean')) return Icons.cleaning_services_rounded;
  if (n.contains('ac') || n.contains('appliance')) return Icons.ac_unit_rounded;
  if (n.contains('plumb')) return Icons.plumbing_rounded;
  if (n.contains('pest')) return Icons.bug_report_rounded;
  if (n.contains('electric')) return Icons.electrical_services_rounded;
  if (n.contains('carpen')) return Icons.carpenter_rounded;
  if (n.contains('paint')) return Icons.format_paint_rounded;
  if (n.contains('garden') || n.contains('lawn')) return Icons.yard_rounded;
  if (n.contains('security') || n.contains('cctv')) return Icons.security_rounded;
  if (n.contains('repair') || n.contains('fix')) return Icons.build_rounded;
  return Icons.home_repair_service_rounded;
}

// ── Ancestor-walking helpers ──────────────────────────────────────────────────

/// Walks the [parentOf] name-chain starting at [nodeName] until reaching a
/// node whose parent is null (the root).  Depth-limited to 10 hops.
/// Falls back to 'Other' for null/empty input or unknown chains.
///
/// [parentOf] maps every non-bookable node's name to its parent's name
/// (null when the node itself is a root category).
String _findRoot(String? nodeName, Map<String, String?> parentOf) {
  if (nodeName == null || nodeName.isEmpty) return 'Other';
  var current = nodeName;
  for (int i = 0; i < 10; i++) {
    if (!parentOf.containsKey(current)) return current; // treat as root
    final parent = parentOf[current];
    if (parent == null) return current; // current IS the root
    current = parent;
  }
  return current;
}

/// Returns [parentName] as the sub-category label when the service's direct
/// parent is NOT itself a root node; returns null when the parent IS the root
/// (service is directly under root — no sub-category level).
String? _subCatName(String? parentName, Map<String, String?> parentOf) {
  if (parentName == null) return null;
  // parentOf[x] == null means x is a root → service parent is root → no sub-cat
  if (!parentOf.containsKey(parentName) || parentOf[parentName] == null) {
    return null;
  }
  return parentName;
}

/// Compound key used to uniquely identify a sub-category inside a root.
String _subKey(String root, String sub) => '$root␟$sub';

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  late int _tab; // 0 = My Services, 1 = All Services, 2 = My Requests
  final Set<String> _addingIds = {};
  final Set<String> _expandedMyParents = {}; // serviceId of expanded parent rows in My Services

  // Wide-only state
  String _selectedCategory = ''; // root category name filter; '' = all
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _expandedRoots = {}; // which root sections are open
  final Set<String> _expandedSubs = {};  // _subKey(root, sub) → open
  final Set<String> _showAllSubs = {};   // _subKey(root, sub) → show all rows

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    if (!isWide) return _buildNarrow();

    final catalogAsync = ref.watch(catalogServicesProvider);
    final vendorAsync = ref.watch(vendorServicesProvider);
    final requestsAsync = ref.watch(myServiceRequestsProvider);
    // nodeName → parentName map for root-category walking.
    // Falls back to {} while loading; the grouped list shows a spinner until
    // catalogAsync also resolves, so an empty map during loading is fine.
    final parentOf = ref.watch(catalogParentMapProvider).valueOrNull ?? const {};

    return VendorScaffold(
      title: 'Services',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WideToolbar(
            tab: _tab,
            myCount: vendorAsync.valueOrNull?.length ?? 0,
            allCount: catalogAsync.valueOrNull?.length ?? 0,
            requestCount: requestsAsync.valueOrNull
                    ?.where((r) => !r.isActiveCustomService)
                    .length ??
                0,
            searchCtrl: _searchCtrl,
            onTabSelect: (i) => setState(() {
              _tab = i;
              _selectedCategory = '';
              _searchCtrl.clear();
            }),
            onCreateService: () => _showCreateServiceDialog(context),
          ),
          if (_tab == 1)
            _CategoryChipsBar(
              catalog: catalogAsync.valueOrNull ?? [],
              parentOf: parentOf,
              selected: _selectedCategory,
              onSelect: (cat) => setState(() => _selectedCategory = cat),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _MyServicesWide(
                  vendorAsync: vendorAsync,
                  onSwitchToAll: () => setState(() => _tab = 1),
                  expandedMyParents: _expandedMyParents,
                  onToggleMyParent: (sid) => setState(() =>
                    _expandedMyParents.contains(sid)
                      ? _expandedMyParents.remove(sid)
                      : _expandedMyParents.add(sid)),
                ),
                _AllServicesWide(
                  catalogAsync: catalogAsync,
                  vendorAsync: vendorAsync,
                  parentOf: parentOf,
                  addingIds: _addingIds,
                  onAdd: _addService,
                  selectedCategory: _selectedCategory,
                  searchQuery: _searchCtrl.text.trim(),
                  expandedRoots: _expandedRoots,
                  expandedSubs: _expandedSubs,
                  showAllSubs: _showAllSubs,
                  onToggleRoot: (root) => setState(() => _expandedRoots.contains(root)
                      ? _expandedRoots.remove(root)
                      : _expandedRoots.add(root)),
                  onToggleSub: (key) => setState(() => _expandedSubs.contains(key)
                      ? _expandedSubs.remove(key)
                      : _expandedSubs.add(key)),
                  onToggleShowAll: (key) => setState(() => _showAllSubs.contains(key)
                      ? _showAllSubs.remove(key)
                      : _showAllSubs.add(key)),
                ),
                _MyRequestsWide(requestsAsync: requestsAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrow() {
    final requestsAsync = ref.watch(myServiceRequestsProvider);
    return VendorScaffold(
      title: 'Services',
      actions: [
        if (_tab != 2)
          VendorSearchButton(
            mode: _tab == 0
                ? VendorSearchMode.myServices
                : VendorSearchMode.allServices,
          ),
        if (_tab == 0)
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Service',
            onPressed: () => _navigateToAdd(context),
          ),
      ],
      child: Column(
        children: [
          _NarrowTabSwitcher(
              selected: _tab, onSelect: (i) => setState(() => _tab = i)),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _MyServicesNarrow(
                    onSwitchToAllServices: () => setState(() => _tab = 1)),
                _AllServicesNarrow(addingIds: _addingIds, onAdd: _addService),
                _MyRequestsNarrow(requestsAsync: requestsAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addService(CatalogService service) async {
    final user = ref.read(currentVendorUserProvider);
    if (user == null) return;
    setState(() => _addingIds.add(service.id));
    try {
      await ref
          .read(assignServicesProvider.notifier)
          .assign(user.id, [service.id]);
      ref.invalidate(vendorServicesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Flexible(child: Text('"${service.name}" added to My Services')),
          ]),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not add service. Please try again.'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ));
      }
    } finally {
      if (mounted) setState(() => _addingIds.remove(service.id));
    }
  }

  void _showCreateServiceDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _CreateServiceDialog(),
    );
  }

  Future<void> _navigateToAdd(BuildContext context) async {
    await context.push(RoutePaths.addService);
    ref.invalidate(vendorServicesProvider);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wide layout — toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _WideToolbar extends StatelessWidget {
  const _WideToolbar({
    required this.tab,
    required this.myCount,
    required this.allCount,
    required this.requestCount,
    required this.searchCtrl,
    required this.onTabSelect,
    required this.onCreateService,
  });

  final int tab;
  final int myCount;
  final int allCount;
  final int requestCount;
  final TextEditingController searchCtrl;
  final void Function(int) onTabSelect;
  final VoidCallback onCreateService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Row(
        children: [
          _TabPill(
            label: 'My Services',
            count: myCount,
            isSelected: tab == 0,
            onTap: () => onTabSelect(0),
          ),
          const SizedBox(width: 8),
          _TabPill(
            label: 'All Services',
            count: allCount,
            isSelected: tab == 1,
            onTap: () => onTabSelect(1),
          ),
          const SizedBox(width: 8),
          _TabPill(
            label: 'My Requests',
            count: requestCount,
            isSelected: tab == 2,
            onTap: () => onTabSelect(2),
          ),
          const Spacer(),
          SizedBox(
            width: 260,
            height: 38,
            child: TextField(
              controller: searchCtrl,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search services...',
                hintStyle:
                    const TextStyle(fontSize: 13, color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 18, color: AppColors.textHint),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchCtrl,
                  builder: (_, val, _) => val.text.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: searchCtrl.clear,
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: AppColors.textHint),
                        ),
                ),
                filled: true,
                fillColor: AppColors.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 148,
            height: 38,
            child: FilledButton.icon(
              onPressed: onCreateService,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Create Service'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: isSelected ? Colors.black : AppColors.border),
        ),
        child: Text(
          count > 0 ? '$label ($count)' : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wide layout — category chips (root categories)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryChipsBar extends StatelessWidget {
  const _CategoryChipsBar({
    required this.catalog,
    required this.parentOf,
    required this.selected,
    required this.onSelect,
  });

  final List<CatalogService> catalog;
  final Map<String, String?> parentOf;
  final String selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final rootNames = catalog
        .map((s) => _findRoot(s.parentName, parentOf))
        .where((n) => n != 'Other')
        .toSet()
        .toList()
      ..sort();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All Categories',
            isSelected: selected.isEmpty,
            onTap: () => onSelect(''),
          ),
          for (final name in rootNames)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _Chip(
                label: name,
                isSelected: selected == name,
                onTap: () => onSelect(name),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: isSelected ? AppColors.textPrimary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wide — All Services: 2-level (Root → Sub-category → Services)
// ─────────────────────────────────────────────────────────────────────────────

class _AllServicesWide extends StatelessWidget {
  const _AllServicesWide({
    required this.catalogAsync,
    required this.vendorAsync,
    required this.parentOf,
    required this.addingIds,
    required this.onAdd,
    required this.selectedCategory,
    required this.searchQuery,
    required this.expandedRoots,
    required this.expandedSubs,
    required this.showAllSubs,
    required this.onToggleRoot,
    required this.onToggleSub,
    required this.onToggleShowAll,
  });

  final AsyncValue<List<CatalogService>> catalogAsync;
  final AsyncValue<List<AssignedService>> vendorAsync;
  final Map<String, String?> parentOf;
  final Set<String> addingIds;
  final Future<void> Function(CatalogService) onAdd;
  final String selectedCategory;
  final String searchQuery;
  final Set<String> expandedRoots;
  final Set<String> expandedSubs;
  final Set<String> showAllSubs;
  final void Function(String) onToggleRoot;
  final void Function(String) onToggleSub;
  final void Function(String) onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString(), onRetry: () {}),
      data: (catalog) {
        final assignedIds =
            (vendorAsync.valueOrNull ?? []).map((s) => s.serviceId).toSet();

        // Filter by search query.
        final q = searchQuery.toLowerCase();
        final filtered = q.isEmpty
            ? catalog
            : catalog.where((s) =>
                s.name.toLowerCase().contains(q) ||
                (s.parentName?.toLowerCase().contains(q) ?? false) ||
                (s.description?.toLowerCase().contains(q) ?? false)).toList();

        // Separate non-bookable parent nodes from bookable services.
        // Parent nodes are rendered as sub-category group headers with their
        // own Add button; they are not placed into the service rows.
        final Map<String, CatalogService> parentNodesByName = {};
        final bookable = <CatalogService>[];
        for (final s in filtered) {
          if (!s.isBookable && s.childrenCount > 0) {
            parentNodesByName[s.name] = s;
          } else {
            bookable.add(s);
          }
        }

        // ── Build 2-level grouping: root → sub → services ─────────────────
        // Map<rootName, Map<subName, List<CatalogService>>>
        // subName == '' means the service is directly under the root (no sub-cat).
        final Map<String, Map<String, List<CatalogService>>> grouped = {};
        for (final s in bookable) {
          final rootName = _findRoot(s.parentName, parentOf);
          final subName = _subCatName(s.parentName, parentOf) ?? '';
          grouped
              .putIfAbsent(rootName, () => {})
              .putIfAbsent(subName, () => [])
              .add(s);
        }

        var visibleRoots = grouped.keys.toList()..sort();

        // Apply root category chip filter.
        if (selectedCategory.isNotEmpty) {
          visibleRoots =
              visibleRoots.where((r) => r == selectedCategory).toList();
        }

        if (visibleRoots.isEmpty) {
          return const EmptyStateView(
            icon: Icons.inventory_2_outlined,
            title: 'No services found',
            subtitle: 'Try a different search term or category.',
          );
        }

        // When searching, auto-expand every visible root and sub-category.
        final effectiveRoots = q.isNotEmpty
            ? visibleRoots.toSet()
            : expandedRoots;

        // Assign a color per root by its sorted index.
        final rootColorIndex = {
          for (int i = 0; i < visibleRoots.length; i++)
            visibleRoots[i]: i % _kCatColors.length,
        };

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: visibleRoots.length,
            itemBuilder: (_, i) {
              final root = visibleRoots[i];
              final subMap = grouped[root]!;
              final catColor = _kCatColors[rootColorIndex[root]!];

              // Sort sub-categories alphabetically; direct (no sub-cat) first.
              final subEntries = subMap.entries.toList()
                ..sort((a, b) {
                  if (a.key.isEmpty) return -1;
                  if (b.key.isEmpty) return 1;
                  return a.key.compareTo(b.key);
                });

              final totalCount =
                  subMap.values.fold(0, (s, l) => s + l.length);

              // Auto-expand sub-categories when searching.
              final effectiveSubs =
                  q.isNotEmpty ? subEntries.map((e) => e.key).toSet() : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RootSection(
                  rootName: root,
                  subEntries: subEntries,
                  catColor: catColor,
                  totalCount: totalCount,
                  isExpanded: effectiveRoots.contains(root),
                  expandedSubs: effectiveSubs ?? expandedSubs,
                  showAllSubs: showAllSubs,
                  addingIds: addingIds,
                  assignedIds: assignedIds,
                  parentNodesByName: parentNodesByName,
                  onToggleRoot: () => onToggleRoot(root),
                  onToggleSub: onToggleSub,
                  onToggleShowAll: onToggleShowAll,
                  onAdd: onAdd,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root category section (expandable)
// ─────────────────────────────────────────────────────────────────────────────

class _RootSection extends StatelessWidget {
  const _RootSection({
    required this.rootName,
    required this.subEntries,
    required this.catColor,
    required this.totalCount,
    required this.isExpanded,
    required this.expandedSubs,
    required this.showAllSubs,
    required this.addingIds,
    required this.assignedIds,
    required this.parentNodesByName,
    required this.onToggleRoot,
    required this.onToggleSub,
    required this.onToggleShowAll,
    required this.onAdd,
  });

  final String rootName;
  final List<MapEntry<String, List<CatalogService>>> subEntries;
  final Color catColor;
  final int totalCount;
  final bool isExpanded;
  final Set<String> expandedSubs;
  final Set<String> showAllSubs;
  final Set<String> addingIds;
  final Set<String> assignedIds;
  final Map<String, CatalogService> parentNodesByName;
  final VoidCallback onToggleRoot;
  final void Function(String) onToggleSub;
  final void Function(String) onToggleShowAll;
  final Future<void> Function(CatalogService) onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Root header ───────────────────────────────────────────────────
          InkWell(
            onTap: onToggleRoot,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(_iconForCategory(rootName), size: 17, color: catColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rootName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$totalCount services',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            const Divider(height: 1, color: AppColors.border),
            // ── Sub-category sections ─────────────────────────────────────
            for (int i = 0; i < subEntries.length; i++) ...[
              _buildSubEntry(context, subEntries[i], i == subEntries.length - 1),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubEntry(
    BuildContext context,
    MapEntry<String, List<CatalogService>> entry,
    bool isLast,
  ) {
    final subName = entry.key;
    final services = entry.value;

    // No sub-category: services are directly under the root.
    // Show them as a simple table without a sub-category header.
    if (subName.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: const [
                Expanded(flex: 3, child: _ColHeader('SERVICE NAME')),
                Expanded(flex: 4, child: _ColHeader('DESCRIPTION')),
                SizedBox(width: 110, child: _ColHeader('PRICE')),
                SizedBox(width: 96, child: _ColHeader('ACTION')),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (int i = 0; i < services.length; i++) ...[
            _ServiceRow(
              service: services[i],
              isAdded: assignedIds.contains(services[i].id),
              isAdding: addingIds.contains(services[i].id),
              onAdd: onAdd,
            ),
            if (i < services.length - 1)
              const Divider(
                  height: 1, color: AppColors.border, indent: 20, endIndent: 20),
          ],
        ],
      );
    }

    // Normal case: sub-category with its own collapsible section.
    final key = _subKey(rootName, subName);
    final isSubExpanded = expandedSubs.contains(key);
    final showAll = showAllSubs.contains(key);
    return _SubCatSection(
      subName: subName,
      services: services,
      isExpanded: isSubExpanded,
      showAll: showAll,
      addingIds: addingIds,
      assignedIds: assignedIds,
      isLast: isLast,
      parentService: parentNodesByName[subName],
      onToggle: () => onToggleSub(key),
      onToggleShowAll: () => onToggleShowAll(key),
      onAdd: onAdd,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-category section (expandable, nested inside a root section)
// ─────────────────────────────────────────────────────────────────────────────

class _SubCatSection extends StatelessWidget {
  const _SubCatSection({
    required this.subName,
    required this.services,
    required this.isExpanded,
    required this.showAll,
    required this.addingIds,
    required this.assignedIds,
    required this.isLast,
    required this.onToggle,
    required this.onToggleShowAll,
    required this.onAdd,
    this.parentService,
  });

  final String subName;
  final List<CatalogService> services;
  final bool isExpanded;
  final bool showAll;
  final Set<String> addingIds;
  final Set<String> assignedIds;
  final bool isLast;
  final VoidCallback onToggle;
  final VoidCallback onToggleShowAll;
  final Future<void> Function(CatalogService) onAdd;
  // When non-null, this catalog node represents the whole sub-category.
  // Its Add button appears on the header row and child rows hide their
  // individual Add buttons (children are covered via ancestor eligibility).
  final CatalogService? parentService;

  @override
  Widget build(BuildContext context) {
    final visible = showAll ? services : services.take(_kPreview).toList();
    final hasMore = services.length > _kPreview;
    final hasParent = parentService != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Sub-category header ───────────────────────────────────────────
        // The expand/collapse InkWell covers only the left portion so that
        // tapping the Add button (right side) does not also toggle expansion.
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.textHint,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          subName,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${services.length} services',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 18, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasParent) ...[
              _ParentAddButton(
                service: parentService!,
                isAdded: assignedIds.contains(parentService!.id),
                isAdding: addingIds.contains(parentService!.id),
                onAdd: onAdd,
              ),
              const SizedBox(width: 16),
            ],
          ],
        ),

        if (isExpanded) ...[
          const Divider(height: 1, color: AppColors.border),
          // Table header — ACTION column is shown only when children have
          // their own Add buttons (i.e. no parent service on the header).
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Expanded(flex: 3, child: _ColHeader('SERVICE NAME')),
                const Expanded(flex: 4, child: _ColHeader('DESCRIPTION')),
                const SizedBox(width: 110, child: _ColHeader('PRICE')),
                const SizedBox(width: 96, child: _ColHeader('ACTION')),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Service rows
          for (int i = 0; i < visible.length; i++) ...[
            _ServiceRow(
              service: visible[i],
              isAdded: assignedIds.contains(visible[i].id),
              isAdding: addingIds.contains(visible[i].id),
              onAdd: onAdd,
            ),
            if (i < visible.length - 1)
              const Divider(
                  height: 1,
                  color: AppColors.border,
                  indent: 20,
                  endIndent: 20),
          ],
          // View all / Show less
          if (hasMore)
            InkWell(
              onTap: onToggleShowAll,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Text(
                  showAll
                      ? 'Show less'
                      : 'View all ${services.length} services →',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 4),
        ],

        if (!isLast)
          const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service row (All Services wide)
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceRow extends StatefulWidget {
  const _ServiceRow({
    required this.service,
    required this.isAdded,
    required this.isAdding,
    required this.onAdd,
  });

  final CatalogService service;
  final bool isAdded;
  final bool isAdding;
  final Future<void> Function(CatalogService) onAdd;

  @override
  State<_ServiceRow> createState() => _ServiceRowState();
}

class _ServiceRowState extends State<_ServiceRow> {
  Future<void> _confirmAdd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Add Service',
        message: 'Add "${widget.service.name}" to your services?',
        confirmLabel: 'Add Service',
      ),
    );
    if (ok == true) widget.onAdd(widget.service);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                s.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  s.description?.isNotEmpty == true ? s.description! : '—',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '₹${s.basePrice.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            SizedBox(width: 96, child: _buildAction()),
          ],
        ),
      ),
    );
  }

  Widget _buildAction() {
    if (widget.isAdding) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.primary),
      );
    }
    if (widget.isAdded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.success.withAlpha(80)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: AppColors.success),
            SizedBox(width: 4),
            Text('Added',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _confirmAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: AppColors.primary),
            SizedBox(width: 3),
            Text('Add',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add button rendered on a sub-category group header when a parent catalog
// node covers that group.  Taps the parent service, not individual children.
// ─────────────────────────────────────────────────────────────────────────────

class _ParentAddButton extends StatelessWidget {
  const _ParentAddButton({
    required this.service,
    required this.isAdded,
    required this.isAdding,
    required this.onAdd,
  });

  final CatalogService service;
  final bool isAdded;
  final bool isAdding;
  final Future<void> Function(CatalogService) onAdd;

  Future<void> _confirmAdd(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Add Service',
        message: 'Add "${service.name}" to your services?',
        confirmLabel: 'Add Service',
      ),
    );
    if (ok == true) onAdd(service);
  }

  @override
  Widget build(BuildContext context) {
    if (isAdding) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.primary),
      );
    }
    if (isAdded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.success.withAlpha(80)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: AppColors.success),
            SizedBox(width: 4),
            Text('Added',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => _confirmAdd(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: AppColors.primary),
            SizedBox(width: 3),
            Text('Add',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wide — My Services (DODO / Custom sub-tabs)
// ─────────────────────────────────────────────────────────────────────────────

class _MyServicesWide extends ConsumerStatefulWidget {
  const _MyServicesWide({
    required this.vendorAsync,
    required this.onSwitchToAll,
    required this.expandedMyParents,
    required this.onToggleMyParent,
  });

  final AsyncValue<List<AssignedService>> vendorAsync;
  final VoidCallback onSwitchToAll;
  final Set<String> expandedMyParents;
  final void Function(String) onToggleMyParent;

  @override
  ConsumerState<_MyServicesWide> createState() => _MyServicesWideState();
}

class _MyServicesWideState extends ConsumerState<_MyServicesWide> {
  int _subTab = 0; // 0 = DODO Services, 1 = Custom Services, 2 = Questions

  @override
  Widget build(BuildContext context) {
    final catalogRaw = ref.watch(catalogServicesProvider).valueOrNull ?? [];
    final allRequests = ref.watch(myServiceRequestsProvider).valueOrNull ?? [];
    final vendorId = ref.watch(currentVendorUserProvider)?.id ?? '';

    final customServices =
        allRequests.where((r) => r.isActiveCustomService).toList();

    final pendingActionFor = {
      // Pending price_change or legacy delete_service rows (via parentRequestId)
      ...allRequests
          .where((r) => (r.isPriceChange || r.isDeleteService) && r.isPending)
          .map((r) => r.parentRequestId)
          .whereType<String>(),
      // Inline deletion: the service itself is pending admin review
      ...customServices.where((r) => r.isPendingDeletion).map((r) => r.id),
    };

    final Map<String, List<CatalogService>> catalogChildrenOf = {};
    for (final cat in catalogRaw) {
      if (cat.isBookable && cat.parentName != null) {
        catalogChildrenOf.putIfAbsent(cat.parentName!, () => []).add(cat);
      }
    }

    final pendingQuestionsCount = vendorId.isEmpty
        ? 0
        : ref
                .watch(vendorQuestionsNotifierProvider(vendorId))
                .valueOrNull
                ?.where((q) => q.isPending)
                .length ??
            0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Sub-tab bar ──────────────────────────────────────────────────────
        _MyServicesSubTabBar(
          selected: _subTab,
          dodoCount: widget.vendorAsync.valueOrNull?.length ?? 0,
          customCount: customServices.length,
          questionsCount: pendingQuestionsCount,
          onSelect: (i) => setState(() => _subTab = i),
        ),

        // ── Content ─────────────────────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: _subTab,
            children: [
              // ── 0: DODO Services ──────────────────────────────────────────
              widget.vendorAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(vendorServicesProvider),
                ),
                data: (services) {
                  if (services.isEmpty) {
                    return EmptyStateView(
                      icon: Icons.home_repair_service_outlined,
                      title: 'No DODO services yet',
                      subtitle:
                          'Browse All Services to add catalog services you offer.',
                      actionLabel: 'Browse All Services',
                      action: widget.onSwitchToAll,
                    );
                  }

                  final assignedParentNames = services
                      .where((s) =>
                          !s.catalog.isBookable &&
                          s.catalog.childrenCount > 0)
                      .map((s) => s.serviceName)
                      .toSet();

                  final Map<String, AssignedService> assignedByCatalogId = {
                    for (final s in services) s.serviceId: s,
                  };

                  final topLevel = services.where((s) {
                    if (!s.catalog.isBookable &&
                        s.catalog.childrenCount > 0) return true;
                    return !assignedParentNames
                        .contains(s.catalog.parentName);
                  }).toList();

                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              child: Row(
                                children: const [
                                  Expanded(
                                      flex: 3,
                                      child: _ColHeader('SERVICE NAME')),
                                  Expanded(
                                      flex: 2,
                                      child: _ColHeader('CATEGORY')),
                                  SizedBox(
                                      width: 120,
                                      child: _ColHeader('BASE PRICE')),
                                  SizedBox(width: 88, child: _ColHeader('')),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.border),
                            for (int i = 0; i < topLevel.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1,
                                    color: AppColors.border,
                                    indent: 20,
                                    endIndent: 20),
                              if (!topLevel[i].catalog.isBookable &&
                                  topLevel[i].catalog.childrenCount > 0)
                                _MyParentGroupRow(
                                  service: topLevel[i],
                                  children: catalogChildrenOf[
                                          topLevel[i].serviceName] ??
                                      [],
                                  assignedByCatalogId: assignedByCatalogId,
                                  isExpanded: widget.expandedMyParents
                                      .contains(topLevel[i].serviceId),
                                  onToggle: () => widget
                                      .onToggleMyParent(topLevel[i].serviceId),
                                )
                              else
                                _MyServiceRow(service: topLevel[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              // ── 1: Custom Services ────────────────────────────────────────
              customServices.isEmpty
                  ? EmptyStateView(
                      icon: Icons.tune_rounded,
                      title: 'No custom services yet',
                      subtitle:
                          'Use "Create Service" to submit a new custom service for admin approval.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                child: Row(
                                  children: const [
                                    Expanded(
                                        flex: 3,
                                        child: _ColHeader('SERVICE NAME')),
                                    SizedBox(
                                        width: 120, child: _ColHeader('PRICE')),
                                    SizedBox(
                                        width: 160, child: _ColHeader('')),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: AppColors.border),
                              for (int i = 0;
                                  i < customServices.length;
                                  i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1,
                                      color: AppColors.border,
                                      indent: 20,
                                      endIndent: 20),
                                _CustomServiceRow(
                                  service: customServices[i],
                                  hasPendingAction: pendingActionFor
                                      .contains(customServices[i].id),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

              // ── 2: Questions ──────────────────────────────────────────────
              vendorId.isEmpty
                  ? const SizedBox.shrink()
                  : _VendorQuestionsPanel(vendorId: vendorId),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyServiceRow extends ConsumerStatefulWidget {
  const _MyServiceRow({required this.service});
  final AssignedService service;

  @override
  ConsumerState<_MyServiceRow> createState() => _MyServiceRowState();
}

class _MyServiceRowState extends ConsumerState<_MyServiceRow> {
  bool _removing = false;

  Future<void> _handleRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Remove Service',
        message: 'Remove "${widget.service.serviceName}" from your services?',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await ref
          .read(removeVendorServiceUseCaseProvider)
          .call(widget.service.id);
      ref.invalidate(vendorServicesProvider);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.serviceName,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (!s.isActive)
                    const Text('Inactive',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textHint)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(s.categoryName ?? '—',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 120,
              child: Text('₹${s.basePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ),
            SizedBox(
              width: 88,
              child: _removing
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 17),
                          color: AppColors.textHint,
                          tooltip: 'Remove service',
                          onPressed: _handleRemove,
                          visualDensity: VisualDensity.compact,
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

// ─────────────────────────────────────────────────────────────────────────────
// My Services — parent group row (wide layout)
// Renders the parent node header + expandable children from the catalog.
// ─────────────────────────────────────────────────────────────────────────────

class _MyParentGroupRow extends ConsumerStatefulWidget {
  const _MyParentGroupRow({
    required this.service,
    required this.children,
    required this.assignedByCatalogId,
    required this.isExpanded,
    required this.onToggle,
  });

  final AssignedService service;
  final List<CatalogService> children;
  final Map<String, AssignedService> assignedByCatalogId;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  ConsumerState<_MyParentGroupRow> createState() => _MyParentGroupRowState();
}

class _MyParentGroupRowState extends ConsumerState<_MyParentGroupRow> {
  bool _removing = false;

  Future<void> _handleRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Remove Service',
        message:
            'Remove "${widget.service.serviceName}" from your services?',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await ref
          .read(removeVendorServiceUseCaseProvider)
          .call(widget.service.id);
      ref.invalidate(vendorServicesProvider);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final childCount = widget.children.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Parent header — always tappable; inner IconButton absorbs remove taps.
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: widget.onToggle,
            child: Container(
              color: Colors.transparent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.serviceName,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$childCount services',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: widget.isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: AppColors.textHint),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      s.categoryName ?? '—',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(
                    width: 120,
                    child: Text('—',
                        style: TextStyle(
                            fontSize: 13.5, color: AppColors.textHint)),
                  ),
                  SizedBox(
                    width: 88,
                    child: _removing
                        ? const Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 17),
                                color: AppColors.textHint,
                                tooltip: 'Remove service',
                                onPressed: _handleRemove,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Expanded children — all catalog children; Edit/Delete shown when
        // the child is also individually registered in vendor_services.
        if (widget.isExpanded)
          for (final child in widget.children) ...[
            const Divider(
                height: 1,
                color: AppColors.border,
                indent: 20,
                endIndent: 20),
            _MyParentChildRow(
              child: child,
              assigned: widget.assignedByCatalogId[child.id],
            ),
          ],
      ],
    );
  }
}

class _MyParentChildRow extends ConsumerStatefulWidget {
  const _MyParentChildRow({
    required this.child,
    required this.assigned,
  });

  final CatalogService child;
  final AssignedService? assigned;

  @override
  ConsumerState<_MyParentChildRow> createState() => _MyParentChildRowState();
}

class _MyParentChildRowState extends ConsumerState<_MyParentChildRow> {
  bool _removing = false;

  Future<void> _handleRemove() async {
    final a = widget.assigned;
    if (a == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Remove Service',
        message: 'Remove "${widget.child.name}" from your services?',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await ref.read(removeVendorServiceUseCaseProvider).call(a.id);
      ref.invalidate(vendorServicesProvider);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.child;
    return Container(
      color: AppColors.background.withAlpha(120),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.textHint,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    c.name,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              c.parentName ?? '—',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              '₹${c.basePrice.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 88,
            child: _removing
                ? const Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.assigned != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 17),
                          color: AppColors.textHint,
                          tooltip: 'Remove service',
                          onPressed: _handleRemove,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared
// ─────────────────────────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textHint,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Narrow layout — unchanged mobile UI
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowTabSwitcher extends StatelessWidget {
  const _NarrowTabSwitcher(
      {required this.selected, required this.onSelect});

  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _NarrowTabBtn(
                label: 'My Services',
                isSelected: selected == 0,
                onTap: () => onSelect(0)),
            const SizedBox(width: 8),
            _NarrowTabBtn(
                label: 'All Services',
                isSelected: selected == 1,
                onTap: () => onSelect(1)),
            const SizedBox(width: 8),
            _NarrowTabBtn(
                label: 'My Requests',
                isSelected: selected == 2,
                onTap: () => onSelect(2)),
          ],
        ),
      ),
    );
  }
}

class _NarrowTabBtn extends StatelessWidget {
  const _NarrowTabBtn(
      {required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: isSelected ? Colors.black : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MyServicesNarrow extends ConsumerStatefulWidget {
  const _MyServicesNarrow({required this.onSwitchToAllServices});
  final VoidCallback onSwitchToAllServices;

  @override
  ConsumerState<_MyServicesNarrow> createState() => _MyServicesNarrowState();
}

class _MyServicesNarrowState extends ConsumerState<_MyServicesNarrow> {
  int _subTab = 0; // 0 = DODO Services, 1 = Custom Services, 2 = Questions
  final Set<String> _expandedMyParents = {};

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(vendorServicesProvider);
    final catalogRaw = ref.watch(catalogServicesProvider).valueOrNull ?? [];
    final allRequests = ref.watch(myServiceRequestsProvider).valueOrNull ?? [];
    final vendorId = ref.watch(currentVendorUserProvider)?.id ?? '';

    final Map<String, List<CatalogService>> catalogChildrenOf = {};
    for (final cat in catalogRaw) {
      if (cat.isBookable && cat.parentName != null) {
        catalogChildrenOf.putIfAbsent(cat.parentName!, () => []).add(cat);
      }
    }

    final customServices =
        allRequests.where((r) => r.isActiveCustomService).toList();

    final pendingActionFor = {
      // Pending price_change or legacy delete_service rows (via parentRequestId)
      ...allRequests
          .where((r) => (r.isPriceChange || r.isDeleteService) && r.isPending)
          .map((r) => r.parentRequestId)
          .whereType<String>(),
      // Inline deletion: the service itself is pending admin review
      ...customServices.where((r) => r.isPendingDeletion).map((r) => r.id),
    };

    final dodoCount = servicesAsync.valueOrNull?.length ?? 0;
    final pendingQuestionsCount = vendorId.isEmpty
        ? 0
        : ref
                .watch(vendorQuestionsNotifierProvider(vendorId))
                .valueOrNull
                ?.where((q) => q.isPending)
                .length ??
            0;

    return Column(
      children: [
        // ── Sub-tab bar ────────────────────────────────────────────────────
        _MyServicesSubTabBar(
          selected: _subTab,
          dodoCount: dodoCount,
          customCount: customServices.length,
          questionsCount: pendingQuestionsCount,
          onSelect: (i) => setState(() => _subTab = i),
        ),

        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: _subTab,
            children: [
              // ── 0: DODO Services ──────────────────────────────────────
              servicesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(vendorServicesProvider),
                ),
                data: (services) {
                  if (services.isEmpty) {
                    return EmptyStateView(
                      icon: Icons.home_repair_service_outlined,
                      title: 'No DODO services yet',
                      subtitle:
                          'Browse All Services to add catalog services you offer.',
                      actionLabel: 'Browse All Services',
                      action: widget.onSwitchToAllServices,
                    );
                  }

                  final assignedParentNames = services
                      .where((s) =>
                          !s.catalog.isBookable &&
                          s.catalog.childrenCount > 0)
                      .map((s) => s.serviceName)
                      .toSet();

                  final Map<String, AssignedService> assignedByCatalogId = {
                    for (final s in services) s.serviceId: s,
                  };

                  final topLevel = services.where((s) {
                    if (!s.catalog.isBookable &&
                        s.catalog.childrenCount > 0) return true;
                    return !assignedParentNames
                        .contains(s.catalog.parentName);
                  }).toList();

                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(vendorServicesProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: topLevel.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final service = topLevel[i];
                        final isParent = !service.catalog.isBookable &&
                            service.catalog.childrenCount > 0;
                        if (isParent) {
                          final isExpanded = _expandedMyParents
                              .contains(service.serviceId);
                          return _MyParentNarrowCard(
                            service: service,
                            children: catalogChildrenOf[
                                    service.serviceName] ??
                                [],
                            assignedByCatalogId: assignedByCatalogId,
                            isExpanded: isExpanded,
                            onToggle: () => setState(() => isExpanded
                                ? _expandedMyParents
                                    .remove(service.serviceId)
                                : _expandedMyParents
                                    .add(service.serviceId)),
                            onRemove: () async {
                              await ref
                                  .read(removeVendorServiceUseCaseProvider)
                                  .call(service.id);
                              ref.invalidate(vendorServicesProvider);
                            },
                          );
                        }
                        return ServiceCard(
                          service: service,
                          onRemove: () async {
                            await ref
                                .read(removeVendorServiceUseCaseProvider)
                                .call(service.id);
                            ref.invalidate(vendorServicesProvider);
                          },
                        );
                      },
                    ),
                  );
                },
              ),

              // ── 1: Custom Services ────────────────────────────────────
              customServices.isEmpty
                  ? EmptyStateView(
                      icon: Icons.tune_rounded,
                      title: 'No custom services yet',
                      subtitle:
                          'Use "Create Service" to submit a new service for admin approval.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(myServiceRequestsProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: customServices.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: AppColors.border,
                            indent: 16,
                            endIndent: 16),
                        itemBuilder: (_, i) => _CustomServiceNarrowCard(
                          service: customServices[i],
                          hasPendingAction: pendingActionFor
                              .contains(customServices[i].id),
                        ),
                      ),
                    ),

              // ── 2: Questions ──────────────────────────────────────────────
              vendorId.isEmpty
                  ? const SizedBox.shrink()
                  : _VendorQuestionsPanel(vendorId: vendorId),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Services sub-tab bar: DODO Services | Custom Services | Questions
// ─────────────────────────────────────────────────────────────────────────────

class _MyServicesSubTabBar extends StatelessWidget {
  const _MyServicesSubTabBar({
    required this.selected,
    required this.dodoCount,
    required this.customCount,
    required this.questionsCount,
    required this.onSelect,
  });

  final int selected;
  final int dodoCount;
  final int customCount;
  final int questionsCount;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _SubTab(
            label: 'DODO Services',
            count: dodoCount,
            isSelected: selected == 0,
            onTap: () => onSelect(0),
          ),
          _SubTab(
            label: 'Custom Services',
            count: customCount,
            isSelected: selected == 1,
            onTap: () => onSelect(1),
          ),
          _SubTab(
            label: 'Questions',
            count: questionsCount,
            isSelected: selected == 2,
            onTap: () => onSelect(2),
          ),
        ],
      ),
    );
  }
}

class _SubTab extends StatelessWidget {
  const _SubTab({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          count > 0 ? '$label ($count)' : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Custom Service row — wide layout
// ─────────────────────────────────────────────────────────────────────────────

class _CustomServiceRow extends ConsumerStatefulWidget {
  const _CustomServiceRow({
    required this.service,
    required this.hasPendingAction,
  });
  final VendorServiceRequestModel service;
  final bool hasPendingAction;

  @override
  ConsumerState<_CustomServiceRow> createState() => _CustomServiceRowState();
}

class _CustomServiceRowState extends ConsumerState<_CustomServiceRow> {
  bool _busy = false;

  Future<void> _toggleActive() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = widget.service;
    final activate = !s.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activate ? 'Activate Service?' : 'Deactivate Service?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activate
                  ? 'Customers will be able to discover and book "${s.serviceName}".'
                  : 'Customers will no longer see "${s.serviceName}".',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: activate
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                    child: Text(activate ? 'Activate' : 'Deactivate'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;

    try {
      await ref.read(servicesDatasourceProvider).toggleCustomServiceActive(
            s.id,
            isActive: activate,
          );
      if (mounted) ref.invalidate(myServiceRequestsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPriceChange() async {
    final s = widget.service;
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final priceCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Price Change'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service: ${s.serviceName}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Current price: ${s.formattedActivePrice}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'New price (₹)',
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final newPrice = double.tryParse(priceCtrl.text.trim());
    if (newPrice == null || newPrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid price.')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(servicesDatasourceProvider).submitPriceChangeRequest(
            vendorId: vendor.id,
            parentRequestId: s.id,
            serviceName: s.serviceName,
            newPrice: newPrice,
          );
      if (mounted) {
        ref.invalidate(myServiceRequestsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price change request submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final s = widget.service;
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Request Service Deletion',
        message:
            'Send a deletion request for "${s.serviceName}" to admin? '
            'The service will only be removed after admin approval.',
        confirmLabel: 'Send Request',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(servicesDatasourceProvider).requestDeletion(
            requestId: s.id,
            vendorId: vendor.id,
          );
      if (mounted) {
        ref.invalidate(myServiceRequestsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deletion request submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final pending = widget.hasPendingAction;
    final sub = ref.watch(mySubscriptionProvider).valueOrNull;
    final canCustomPrice = sub != null && sub.isActive && (sub.plan?.allowCustomPrice ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Service name
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.serviceName,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (pending) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Pending admin review',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
                  ),
                ],
              ],
            ),
          ),
          // Price
          SizedBox(
            width: 120,
            child: Text(
              s.formattedActivePrice,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // Action buttons
          SizedBox(
            width: 200,
            child: _busy
                ? const Center(
                    child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(
                          s.isActive
                              ? Icons.toggle_on_rounded
                              : Icons.toggle_off_rounded,
                          size: 36,
                        ),
                        tooltip: s.isActive ? 'Deactivate' : 'Activate',
                        color: s.isActive ? AppColors.success : AppColors.textHint,
                        onPressed: _toggleActive,
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 26),
                        tooltip: 'Configure service',
                        color: AppColors.textSecondary,
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => VendorServiceConfigDialog(
                            serviceId: s.id,
                            serviceName: s.serviceName,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 26),
                        tooltip: pending ? 'Request pending' : 'Edit price',
                        color: (pending || !canCustomPrice)
                            ? AppColors.textHint
                            : AppColors.textSecondary,
                        onPressed: (pending || !canCustomPrice) ? null : _requestPriceChange,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 26),
                        tooltip: pending ? 'Request pending' : 'Request deletion',
                        color: pending ? AppColors.textHint : AppColors.error,
                        onPressed: pending ? null : _requestDeletion,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Service card — narrow layout
// ─────────────────────────────────────────────────────────────────────────────

class _CustomServiceNarrowCard extends ConsumerStatefulWidget {
  const _CustomServiceNarrowCard({
    required this.service,
    required this.hasPendingAction,
  });
  final VendorServiceRequestModel service;
  final bool hasPendingAction;

  @override
  ConsumerState<_CustomServiceNarrowCard> createState() =>
      _CustomServiceNarrowCardState();
}

class _CustomServiceNarrowCardState
    extends ConsumerState<_CustomServiceNarrowCard> {
  bool _busy = false;

  Future<void> _toggleActive() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = widget.service;
    final activate = !s.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activate ? 'Activate Service?' : 'Deactivate Service?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activate
                  ? 'Customers will be able to discover and book "${s.serviceName}".'
                  : 'Customers will no longer see "${s.serviceName}".',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: activate
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                    child: Text(activate ? 'Activate' : 'Deactivate'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;

    try {
      await ref.read(servicesDatasourceProvider).toggleCustomServiceActive(
            s.id,
            isActive: activate,
          );
      if (mounted) ref.invalidate(myServiceRequestsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPriceChange() async {
    final s = widget.service;
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final priceCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Price Change'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current price: ${s.formattedActivePrice}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'New price (₹)',
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final newPrice = double.tryParse(priceCtrl.text.trim());
    if (newPrice == null || newPrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid price.')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(servicesDatasourceProvider).submitPriceChangeRequest(
            vendorId: vendor.id,
            parentRequestId: s.id,
            serviceName: s.serviceName,
            newPrice: newPrice,
          );
      if (mounted) {
        ref.invalidate(myServiceRequestsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Price change request submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final s = widget.service;
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Request Deletion',
        message:
            'Send a deletion request for "${s.serviceName}" to admin? '
            'The service will only be removed after approval.',
        confirmLabel: 'Send Request',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(servicesDatasourceProvider).requestDeletion(
            requestId: s.id,
            vendorId: vendor.id,
          );
      if (mounted) {
        ref.invalidate(myServiceRequestsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deletion request submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final pending = widget.hasPendingAction;
    final sub = ref.watch(mySubscriptionProvider).valueOrNull;
    final canCustomPrice = sub != null && sub.isActive && (sub.plan?.allowCustomPrice ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.serviceName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  s.formattedActivePrice,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (pending) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Pending admin review',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
                  ),
                ],
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    s.isActive
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    size: 22,
                  ),
                  tooltip: s.isActive ? 'Deactivate' : 'Activate',
                  color: s.isActive ? AppColors.success : AppColors.textHint,
                  onPressed: _toggleActive,
                ),
                IconButton(
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  tooltip: 'Configure service',
                  color: AppColors.textSecondary,
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => VendorServiceConfigDialog(
                      serviceId: s.id,
                      serviceName: s.serviceName,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: pending ? 'Request pending' : 'Edit price',
                  color: (pending || !canCustomPrice) ? AppColors.textHint : AppColors.textSecondary,
                  onPressed: (pending || !canCustomPrice) ? null : _requestPriceChange,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: pending ? 'Request pending' : 'Request deletion',
                  color: pending ? AppColors.textHint : AppColors.error,
                  onPressed: pending ? null : _requestDeletion,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Services — parent group card (narrow layout)
// ─────────────────────────────────────────────────────────────────────────────

class _MyParentNarrowCard extends ConsumerStatefulWidget {
  const _MyParentNarrowCard({
    required this.service,
    required this.children,
    required this.assignedByCatalogId,
    required this.isExpanded,
    required this.onToggle,
    required this.onRemove,
  });

  final AssignedService service;
  final List<CatalogService> children;
  final Map<String, AssignedService> assignedByCatalogId;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Future<void> Function() onRemove;

  @override
  ConsumerState<_MyParentNarrowCard> createState() =>
      _MyParentNarrowCardState();
}

class _MyParentNarrowCardState extends ConsumerState<_MyParentNarrowCard> {
  bool _removing = false;

  Future<void> _handleRemove() async {
    if (_removing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Remove Service',
        message:
            'Remove "${widget.service.serviceName}" from your services?',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await widget.onRemove();
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _removeChild(CatalogService cat, AssignedService a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Remove Service',
        message: 'Remove "${cat.name}" from your services?',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(removeVendorServiceUseCaseProvider).call(a.id);
    ref.invalidate(vendorServicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final theme = Theme.of(context);
    final childCount = widget.children.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Parent header — always tappable
          InkWell(
            onTap: widget.onToggle,
            borderRadius: widget.isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.serviceName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$childCount services',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.textHint),
                  ),
                  if (_removing)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: AppColors.textHint,
                      tooltip: 'Remove service',
                      onPressed: _handleRemove,
                    ),
                ],
              ),
            ),
          ),
          // Expanded catalog children; Edit/Delete shown only when individually registered.
          if (widget.isExpanded) ...[
            const Divider(height: 1, color: AppColors.border),
            for (final child in widget.children) ...[
              if (child != widget.children.first)
                const Divider(
                    height: 1, color: AppColors.border, indent: 16),
              _NarrowChildTile(
                child: child,
                assigned: widget.assignedByCatalogId[child.id],
                onRemove: () async {
                  final a = widget.assignedByCatalogId[child.id];
                  if (a != null) await _removeChild(child, a);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _NarrowChildTile extends StatefulWidget {
  const _NarrowChildTile({
    required this.child,
    required this.assigned,
    required this.onRemove,
  });

  final CatalogService child;
  final AssignedService? assigned;
  final Future<void> Function() onRemove;

  @override
  State<_NarrowChildTile> createState() => _NarrowChildTileState();
}

class _NarrowChildTileState extends State<_NarrowChildTile> {
  bool _removing = false;

  Future<void> _handleRemove() async {
    if (_removing || widget.assigned == null) return;
    setState(() => _removing = true);
    try {
      await widget.onRemove();
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.child;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: const BoxDecoration(
              color: AppColors.textHint,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '₹${c.basePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
          if (_removing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (widget.assigned != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.textHint,
              tooltip: 'Remove service',
              onPressed: _handleRemove,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _AllServicesNarrow extends ConsumerWidget {
  const _AllServicesNarrow(
      {required this.addingIds, required this.onAdd});

  final Set<String> addingIds;
  final Future<void> Function(CatalogService) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogServicesProvider);
    final assignedAsync = ref.watch(vendorServicesProvider);
    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(catalogServicesProvider)),
      data: (catalog) {
        if (catalog.isEmpty) {
          return const EmptyStateView(
            icon: Icons.inventory_2_outlined,
            title: 'No services in catalog',
            subtitle: 'The admin has not added any services yet.',
          );
        }
        final assignedIds = (assignedAsync.valueOrNull ?? [])
            .map((s) => s.serviceId)
            .toSet();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(catalogServicesProvider);
            ref.invalidate(vendorServicesProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: catalog.length,
            separatorBuilder: (_, _) => const Divider(
                height: 1, color: AppColors.border, indent: 76),
            itemBuilder: (_, i) {
              final service = catalog[i];
              final isAdded = assignedIds.contains(service.id);
              final isAdding = addingIds.contains(service.id);
              return _NarrowCatalogTile(
                service: service,
                isAdded: isAdded,
                isAdding: isAdding,
                onAdd: (isAdded || isAdding) ? null : () => onAdd(service),
              );
            },
          ),
        );
      },
    );
  }
}

class _NarrowCatalogTile extends StatelessWidget {
  const _NarrowCatalogTile({
    required this.service,
    required this.isAdded,
    required this.isAdding,
    this.onAdd,
  });

  final CatalogService service;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.home_repair_service_rounded,
                size: 22, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (service.parentName != null) ...[
                      Flexible(
                          child: Text(service.parentName!,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      const _NarrowDot(),
                    ],
                    Text('₹${service.basePrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildAction(context),
        ],
      ),
    );
  }

  Future<void> _confirmAdd(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Add Service',
        message: 'Add "${service.name}" to your services?',
        confirmLabel: 'Add Service',
      ),
    );
    if (ok == true) onAdd?.call();
  }

  Widget _buildAction(BuildContext context) {
    if (isAdding) {
      return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary));
    }
    if (isAdded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.success.withAlpha(90)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: AppColors.success),
            SizedBox(width: 4),
            Text('Added',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: onAdd == null ? null : () => _confirmAdd(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(100),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: Colors.white),
            SizedBox(width: 3),
            Text('Add',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _NarrowDot extends StatelessWidget {
  const _NarrowDot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        width: 3,
        height: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: AppColors.textHint, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Requests — wide layout
// ─────────────────────────────────────────────────────────────────────────────

class _MyRequestsWide extends StatelessWidget {
  const _MyRequestsWide({required this.requestsAsync});

  final AsyncValue<List<VendorServiceRequestModel>> requestsAsync;

  @override
  Widget build(BuildContext context) {
    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString(), onRetry: () {}),
      data: (all) {
        // Active custom services are shown in My Services → Custom Services.
        // Exclude them here to avoid showing the same service twice.
        final requests = all.where((r) => !r.isActiveCustomService).toList();
        if (requests.isEmpty) {
          return const EmptyStateView(
            icon: Icons.inbox_outlined,
            title: 'No requests yet',
            subtitle: 'Use "Create Service" to request a new service.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(children: [
                      Expanded(flex: 3, child: _ColHeader('SERVICE NAME')),
                      SizedBox(width: 120, child: _ColHeader('PRICE')),
                      SizedBox(width: 140, child: _ColHeader('SUBMITTED')),
                      SizedBox(width: 140, child: _ColHeader('STATUS')),
                      SizedBox(width: 48, child: _ColHeader('')),
                    ]),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  for (int i = 0; i < requests.length; i++) ...[
                    _RequestRow(request: requests[i]),
                    if (i < requests.length - 1)
                      const Divider(
                          height: 1,
                          color: AppColors.border,
                          indent: 20,
                          endIndent: 20),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RequestRow extends ConsumerStatefulWidget {
  const _RequestRow({required this.request});
  final VendorServiceRequestModel request;

  @override
  ConsumerState<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends ConsumerState<_RequestRow> {
  bool _deleting = false;

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Delete Request',
        message: 'Are you sure you want to delete this service request?',
        confirmLabel: 'Delete',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    final vendorId = ref.read(currentVendorUserProvider)?.id;
    if (vendorId == null || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(servicesDatasourceProvider)
          .deleteServiceRequest(widget.request.id, vendorId);
      if (mounted) ref.invalidate(myServiceRequestsProvider);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service name + type badge + rejection reason
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        r.serviceName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!r.isNewService) ...[
                      const SizedBox(width: 8),
                      _RequestTypeBadge(label: r.requestTypeLabel),
                    ],
                  ],
                ),
                if (r.isRejected &&
                    r.rejectionReason != null &&
                    r.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 12, color: AppColors.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          r.rejectionReason!,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.error),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Price (show new_price for price_change requests, active_price for new_service)
          SizedBox(
            width: 120,
            child: Text(
              r.isPriceChange ? r.formattedNewPrice : r.formattedActivePrice,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // Date
          SizedBox(
            width: 140,
            child: Text(
              r.formattedDate,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          // Status
          SizedBox(
            width: 140,
            child: _RequestStatusBadge(status: r.status),
          ),
          // Delete (pending only)
          SizedBox(
            width: 48,
            child: r.isPending
                ? (_deleting
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.error),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18),
                        color: AppColors.textHint,
                        tooltip: 'Delete request',
                        onPressed: _handleDelete,
                      ))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Requests — narrow layout
// ─────────────────────────────────────────────────────────────────────────────

class _MyRequestsNarrow extends StatelessWidget {
  const _MyRequestsNarrow({required this.requestsAsync});

  final AsyncValue<List<VendorServiceRequestModel>> requestsAsync;

  @override
  Widget build(BuildContext context) {
    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString(), onRetry: () {}),
      data: (all) {
        // Active custom services are shown in My Services → Custom Services.
        // Exclude them here to avoid showing the same service twice.
        final requests = all.where((r) => !r.isActiveCustomService).toList();
        if (requests.isEmpty) {
          return const EmptyStateView(
            icon: Icons.inbox_outlined,
            title: 'No requests yet',
            subtitle: 'Tap the + button in My Services to request a new service.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) => _NarrowRequestTile(request: requests[i]),
          ),
        );
      },
    );
  }
}

class _NarrowRequestTile extends ConsumerStatefulWidget {
  const _NarrowRequestTile({required this.request});
  final VendorServiceRequestModel request;

  @override
  ConsumerState<_NarrowRequestTile> createState() =>
      _NarrowRequestTileState();
}

class _NarrowRequestTileState extends ConsumerState<_NarrowRequestTile> {
  bool _deleting = false;

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Delete Request',
        message: 'Are you sure you want to delete this service request?',
        confirmLabel: 'Delete',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    final vendorId = ref.read(currentVendorUserProvider)?.id;
    if (vendorId == null || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(servicesDatasourceProvider)
          .deleteServiceRequest(widget.request.id, vendorId);
      if (mounted) ref.invalidate(myServiceRequestsProvider);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.serviceName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!r.isNewService) ...[
                      const SizedBox(height: 3),
                      _RequestTypeBadge(label: r.requestTypeLabel),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RequestStatusBadge(status: r.status),
              if (r.isPending) ...[
                const SizedBox(width: 4),
                _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.error),
                      )
                    : GestureDetector(
                        onTap: _handleDelete,
                        child: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.textHint),
                      ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                r.isPriceChange ? r.formattedNewPrice : r.formattedActivePrice,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const _NarrowDot(),
              Text(
                r.formattedDate,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (r.isRejected &&
              r.rejectionReason != null &&
              r.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.rejectionReason!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestStatusBadge extends StatelessWidget {
  const _RequestStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'needs_catalog' => ('Needs Catalog', AppColors.primary),
      'completed' => ('Completed', AppColors.success),
      'rejected' => ('Rejected', AppColors.error),
      'pending_deletion' => ('Deletion Pending', const Color(0xFFF59E0B)),
      'deleted' => ('Deleted', AppColors.error),
      _ => ('Pending', const Color(0xFFF59E0B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _RequestTypeBadge extends StatelessWidget {
  const _RequestTypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(18),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Service Request Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CreateServiceDialog extends ConsumerStatefulWidget {
  const _CreateServiceDialog();

  @override
  ConsumerState<_CreateServiceDialog> createState() =>
      _CreateServiceDialogState();
}

class _CreateServiceDialogState extends ConsumerState<_CreateServiceDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _picker = ImagePicker();
  XFile? _pickedFile;
  Uint8List? _pickedImageBytes;
  bool _submitting = false;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    _priceCtrl.addListener(_onPriceChanged);
  }

  void _onPriceChanged() {
    final text = _priceCtrl.text;
    final String? error;
    if (text.isEmpty) {
      error = null; // clear error while user is re-typing from scratch
    } else {
      error = double.tryParse(text.trim()) == null
          ? 'Price must contain numbers only.'
          : null;
    }
    if (error != _priceError) setState(() => _priceError = error);
  }

  @override
  void dispose() {
    _priceCtrl.removeListener(_onPriceChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (mounted) {
      setState(() {
        _pickedFile = image;
        _pickedImageBytes = bytes;
      });
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service name is required.')),
      );
      return;
    }

    final priceText = _priceCtrl.text.trim();
    if (priceText.isEmpty || double.tryParse(priceText) == null) {
      setState(() => _priceError = 'Price must contain numbers only.');
      return;
    }

    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    setState(() => _submitting = true);
    try {
      // Enforce max_custom_services limit before inserting.
      final sub = ref.read(mySubscriptionProvider).valueOrNull;
      if (sub?.plan?.isMaxCustomServicesEnabled == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Custom service creation is not included in your plan.'),
            backgroundColor: AppColors.error,
          ));
        }
        return;
      }
      final limit = sub?.plan?.maxCustomServices;
      if (limit != null) {
        final requests = ref.read(myServiceRequestsProvider).valueOrNull ?? [];
        final usedCount =
            requests.where((r) => r.isActiveCustomService).length;
        if (usedCount >= limit) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Custom service limit ($limit) reached.'),
              backgroundColor: AppColors.error,
            ));
          }
          return;
        }
      }

      final ds = ref.read(servicesDatasourceProvider);

      String? imageUrl;
      if (_pickedImageBytes != null && _pickedFile != null) {
        imageUrl = await ds.uploadServiceRequestImage(
          vendorId: vendor.id,
          bytes: _pickedImageBytes!,
          mimeType: _pickedFile!.mimeType ?? 'image/jpeg',
        );
      }

      final priceText = _priceCtrl.text.trim();
      final price =
          priceText.isNotEmpty ? double.tryParse(priceText) : null;

      await ds.submitServiceRequest(
        vendorId: vendor.id,
        serviceName: name,
        description: _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : null,
        price: price,
        imageUrl: imageUrl,
      );

      ref.invalidate(myServiceRequestsProvider);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Service request submitted successfully.'),
          ]),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(mySubscriptionProvider).valueOrNull;
    final featureEnabled = sub?.plan?.isMaxCustomServicesEnabled ?? true;
    final limit = featureEnabled ? sub?.plan?.maxCustomServices : null;
    final usedCount = (featureEnabled && limit != null)
        ? (ref.watch(myServiceRequestsProvider).valueOrNull ?? [])
            .where((r) => r.isActiveCustomService)
            .length
        : 0;
    final atLimit = !featureEnabled || (limit != null && usedCount >= limit);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Request a New Service',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Submit a request to add a new service to the catalog.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (!featureEnabled || limit != null) ...[
                const SizedBox(height: 8),
                if (!featureEnabled)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withAlpha(80)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.block_rounded,
                                size: 15, color: AppColors.error),
                            const SizedBox(width: 6),
                            const Text(
                              'Not Included in Your Plan',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Custom service creation is not included in your current subscription plan.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sub?.isActive == true
                              ? 'You can switch to a plan that includes this feature when your current subscription expires.'
                              : 'Upgrade your plan to unlock custom service creation.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            context.push(RoutePaths.browsePlans);
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Plans',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else if (atLimit)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withAlpha(80)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.block_rounded,
                                size: 15, color: AppColors.error),
                            const SizedBox(width: 6),
                            const Text(
                              'Custom Service Limit Reached',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "You've used $usedCount of $limit custom "
                          'service${limit == 1 ? '' : 's'} allowed by your plan.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sub?.isActive == true
                              ? 'You can switch to a higher-tier plan when your current subscription expires.'
                              : 'Upgrade your subscription plan to create more custom services.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            context.push(RoutePaths.browsePlans);
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Plans',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha(18),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.success.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text(
                          '$usedCount of $limit custom '
                          'service${limit == 1 ? '' : 's'} used',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // Service Name
              _DialogFieldLabel('Service Name', required: true),
              const SizedBox(height: 6),
              _DialogTextField(
                controller: _nameCtrl,
                hint: 'e.g. Deep Sofa Cleaning',
              ),
              const SizedBox(height: 16),

              // Description
              _DialogFieldLabel('Description'),
              const SizedBox(height: 6),
              _DialogTextField(
                controller: _descCtrl,
                hint: 'Briefly describe the service...',
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Price
              _DialogFieldLabel('Price', required: true),
              const SizedBox(height: 6),
              _DialogTextField(
                controller: _priceCtrl,
                hint: '0',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixText: '₹ ',
              ),
              if (_priceError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _priceError!,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.error),
                ),
              ],
              const SizedBox(height: 16),

              // Image
              _DialogFieldLabel('Service Image'),
              const SizedBox(height: 6),
              _DialogImagePicker(
                pickedBytes: _pickedImageBytes,
                onTap: _pickImage,
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        fixedSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_submitting || atLimit) ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        fixedSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Send Request'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogFieldLabel extends StatelessWidget {
  const _DialogFieldLabel(this.label, {this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(fontSize: 12.5, color: AppColors.error),
          ),
      ],
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.prefixText,
  });
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefixText,
        hintStyle:
            const TextStyle(fontSize: 13, color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _DialogImagePicker extends StatelessWidget {
  const _DialogImagePicker({
    required this.pickedBytes,
    required this.onTap,
  });
  final Uint8List? pickedBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (pickedBytes != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              pickedBytes!,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: const Text('Change'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 20, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'Select Image',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vendor Questions Panel — shows customer questions for vendor's custom services
// ─────────────────────────────────────────────────────────────────────────────

class _VendorQuestionsPanel extends ConsumerStatefulWidget {
  const _VendorQuestionsPanel({required this.vendorId});
  final String vendorId;

  @override
  ConsumerState<_VendorQuestionsPanel> createState() =>
      _VendorQuestionsPanelState();
}

class _VendorQuestionsPanelState
    extends ConsumerState<_VendorQuestionsPanel> {
  @override
  Widget build(BuildContext context) {
    final questionsAsync =
        ref.watch(vendorQuestionsNotifierProvider(widget.vendorId));
    final notifier =
        ref.read(vendorQuestionsNotifierProvider(widget.vendorId).notifier);

    return questionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            const Text('Failed to load questions',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: notifier.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (questions) {
        if (questions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.help_outline_rounded,
                      size: 52, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text(
                    'No customer questions yet',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Questions from customers about your custom services will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: questions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _VendorQuestionTile(
              question: questions[i],
              onAnswer: () => _openAnswerSheet(ctx, notifier, questions[i]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAnswerSheet(
    BuildContext context,
    VendorQuestionsNotifier notifier,
    CustomerQuestionModel question,
  ) async {
    final confirmed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VendorAnswerSheet(question: question),
    );
    if (confirmed != null && confirmed.isNotEmpty) {
      try {
        await notifier.answerQuestion(
            questionId: question.id, answer: confirmed);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Answer published.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to publish: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

class _VendorQuestionTile extends StatelessWidget {
  const _VendorQuestionTile({
    required this.question,
    required this.onAnswer,
  });

  final CustomerQuestionModel question;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final isPending = question.isPending;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isPending
                    ? Icons.help_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 16,
                color: isPending
                    ? const Color(0xFFF59E0B)
                    : AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.question,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (question.customerName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'from ${question.customerName}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isPending)
                GestureDetector(
                  onTap: onAnswer,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Answer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (question.isAnswered && question.answer != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FAF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Text(
                question.answer!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VendorAnswerSheet extends StatefulWidget {
  const _VendorAnswerSheet({required this.question});

  final CustomerQuestionModel question;

  @override
  State<_VendorAnswerSheet> createState() => _VendorAnswerSheetState();
}

class _VendorAnswerSheetState extends State<_VendorAnswerSheet> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.question.answer ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Answer Question',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.question.question,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Write your answer here…',
              hintStyle: const TextStyle(color: AppColors.textHint),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(12),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Publish Answer',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final answer = _ctrl.text.trim();
    if (answer.isEmpty) {
      setState(() => _error = 'Please enter your answer.');
      return;
    }
    Navigator.of(context).pop(answer);
  }
}
