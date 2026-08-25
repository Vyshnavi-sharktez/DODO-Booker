import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_registry.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../core/widgets/app_header.dart';
import '../../../routes/app_router.dart';
import '../models/catalog_node_model.dart';
import '../providers/catalog_providers.dart';
import '../utils/catalog_launcher.dart';
import 'package:go_router/go_router.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const double _kSidebarWidth = 280.0;
const double _kBreakpoint   = 900.0;
const Color  _kBorderColor  = Color(0xFFE5E5E5);
const Color  _kBgRight      = Color(0xFFF7F7F7);
const Color  _kTextDark     = Color(0xFF111111);
const Color  _kTextMid      = Color(0xFF333333);
const Color  _kTextMuted    = Color(0xFF6B6B6B);

// ── Screen ───────────────────────────────────────────────────────────────────

class CategoryExplorerScreen extends ConsumerStatefulWidget {
  final String? initialCategoryId;
  final String? initialSubId;
  /// The exact node the user tapped. When set, the screen resolves the correct
  /// root ancestor automatically (handles L2 and L3 hierarchy depths).
  final CatalogNodeModel? initialNode;

  const CategoryExplorerScreen({
    super.key,
    this.initialCategoryId,
    this.initialSubId,
    this.initialNode,
  });

  @override
  ConsumerState<CategoryExplorerScreen> createState() =>
      _CategoryExplorerScreenState();
}

class _CategoryExplorerScreenState
    extends ConsumerState<CategoryExplorerScreen> {
  bool _scrolled = false;
  String? _activeCategoryId;
  String? _activeSubId; // null = "All" within the current browse context
  String? _browseNodeId; // set when Browse is clicked; overrides chip root for chips+cards
  // Each entry is the (browseNodeId, activeSubId) state before the last Browse.
  // Popping restores the exact previous level; when empty, back pops the route.
  final _browseHistory = <({String? nodeId, String? subId})>[];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveInitialState());
  }

  /// Async resolution: handles L1/L2/L3 nodes by walking up the catalog tree.
  /// Always sets _activeCategoryId to a real root, never stale/wrong state.
  Future<void> _resolveInitialState() async {
    if (_initialized || !mounted) return;
    _initialized = true;

    List<CatalogNodeModel> roots;
    try {
      roots = await ref.read(rootCatalogNodesProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final activeRoots =
        roots.where((n) => n.availabilityStatus != 'hidden').toList();
    if (activeRoots.isEmpty) return;

    final node = widget.initialNode;
    if (node != null) {
      await _resolveFromNode(node, activeRoots);
    } else {
      _resolveFromIds(activeRoots);
    }
  }

  /// Legacy path: caller supplied explicit categoryId/subId strings.
  void _resolveFromIds(List<CatalogNodeModel> roots) {
    if (!mounted) return;
    final wantId = widget.initialCategoryId;
    final match = wantId != null
        ? roots.firstWhere((r) => r.id == wantId, orElse: () => roots.first)
        : roots.first;
    setState(() {
      _activeCategoryId = match.id;
      _activeSubId = widget.initialSubId;
    });
  }

  /// Node-aware path: resolves the root ancestor for L2 and L3 nodes.
  Future<void> _resolveFromNode(
      CatalogNodeModel node, List<CatalogNodeModel> roots) async {
    if (!mounted) return;

    // Node IS a root category.
    if (node.isRoot && roots.any((r) => r.id == node.id)) {
      setState(() {
        _activeCategoryId = node.id;
        _activeSubId = null;
      });
      return;
    }

    final parentId = node.parentId;
    if (parentId == null) {
      if (roots.isNotEmpty) {
        setState(() { _activeCategoryId = roots.first.id; _activeSubId = null; });
      }
      return;
    }

    // L2 node: direct parent is a root — select that root, node as chip.
    if (roots.any((r) => r.id == parentId)) {
      setState(() { _activeCategoryId = parentId; _activeSubId = node.id; });
      return;
    }

    // L3 node: direct parent is NOT a root. Fetch parent to find grandparent.
    CatalogNodeModel? parentNode;
    try {
      parentNode = await ref.read(catalogNodeProvider(parentId).future);
    } catch (_) {}
    if (!mounted) return;

    final grandparentId = parentNode?.parentId;
    if (grandparentId != null && roots.any((r) => r.id == grandparentId)) {
      // grandparent = root, parent (L2) becomes the selected chip,
      // and the clicked L3 node appears as a card inside that chip.
      setState(() { _activeCategoryId = grandparentId; _activeSubId = parentId; });
      return;
    }

    // Fallback: first root, no sub — at least nothing wrong is shown.
    if (roots.isNotEmpty) {
      setState(() { _activeCategoryId = roots.first.id; _activeSubId = null; });
    }
  }

  bool _onScroll(ScrollNotification n) {
    final s = n.metrics.pixels > 8;
    if (s != _scrolled) setState(() => _scrolled = s);
    return false;
  }

  void _selectCategory(String id) {
    if (_activeCategoryId == id) return;
    setState(() {
      _activeCategoryId = id;
      _activeSubId = null;
      _browseNodeId = null;
      _browseHistory.clear(); // root change resets all browse history
    });
  }

  void _selectSub(String? id) {
    if (_activeSubId == id) return;
    setState(() => _activeSubId = id);
  }

  // Called when the user clicks Browse on any card.
  // Pushes the current state onto the history stack before changing, so the
  // back button can restore the exact previous level at any depth.
  void _setBrowseNode(String id) {
    _browseHistory.add((nodeId: _browseNodeId, subId: _activeSubId));
    setState(() {
      _browseNodeId = id;
      _activeSubId = null;
    });
  }

  // Back logic: if browse history exists, restore the previous browse state.
  // Otherwise pop the route to return to wherever the user navigated from.
  void _goBack(BuildContext context) {
    if (_browseHistory.isNotEmpty) {
      final prev = _browseHistory.removeLast();
      setState(() {
        _browseNodeId = prev.nodeId;
        _activeSubId = prev.subId;
      });
    } else {
      context.canPop() ? context.pop() : context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootsAsync = ref.watch(rootCatalogNodesProvider);
    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = w >= _kBreakpoint;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppHeader(
        onLogoTap: () => context.go(AppRoutes.home),
        onProfileTap: () => context.push(AppRoutes.profile),
        isScrolled: _scrolled,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: rootsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(child: Text('Could not load categories')),
          data: (roots) {
            final activeRoots =
                roots.where((n) => n.availabilityStatus != 'hidden').toList();
            if (activeRoots.isEmpty) {
              return const Center(child: Text('No categories available'));
            }
            // Async resolution in progress — show spinner until ready.
            if (_activeCategoryId == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final catId = _activeCategoryId!;
            final catName = activeRoots
                .firstWhere((r) => r.id == catId,
                    orElse: () => activeRoots.first)
                .name;

            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _kSidebarWidth,
                    child: _Sidebar(
                      roots: activeRoots,
                      activeCategoryId: catId,
                      onSelect: _selectCategory,
                    ),
                  ),
                  const VerticalDivider(width: 1, color: _kBorderColor),
                  Expanded(
                    child: _RightPane(
                      categoryId: catId,
                      categoryName: catName,
                      browseNodeId: _browseNodeId,
                      activeSubId: _activeSubId,
                      onSubSelected: _selectSub,
                      onBrowseNode: _setBrowseNode,
                      onBack: () => _goBack(context),
                    ),
                  ),
                ],
              );
            }

            // Mobile: category pills on top, pane below.
            return Column(
              children: [
                _MobileCategoryPillRow(
                  roots: activeRoots,
                  activeCategoryId: catId,
                  onSelect: _selectCategory,
                ),
                Expanded(
                  child: _RightPane(
                    categoryId: catId,
                    categoryName: catName,
                    browseNodeId: _browseNodeId,
                    activeSubId: _activeSubId,
                    onSubSelected: _selectSub,
                    onBrowseNode: _setBrowseNode,
                    onBack: () => _goBack(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Desktop Sidebar ──────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<CatalogNodeModel> roots;
  final String activeCategoryId;
  final ValueChanged<String> onSelect;

  const _Sidebar({
    required this.roots,
    required this.activeCategoryId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
              child: Text(
                'Categories',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark,
                ),
              ),
            ),
            for (final node in roots) ...[
              _SidebarRow(
                node: node,
                isActive: node.id == activeCategoryId,
                onTap: () => onSelect(node.id),
              ),
              const SizedBox(height: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  final CatalogNodeModel node;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarRow({
    required this.node,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active || _hovered
                ? const Color(0xFFF7F7F7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Icon(
                  IconRegistry.resolve(widget.node.iconKey, widget.node.name),
                  size: 16,
                  color: active ? _kTextDark : _kTextMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.node.name,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? _kTextDark : _kTextMid,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (widget.node.childrenCount > 0)
                Text(
                  '${widget.node.childrenCount}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _kTextMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCategoriesRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        children: [
          const SizedBox(width: 26),
          const SizedBox(width: 10),
          Text(
            'More Categories',
            style: GoogleFonts.inter(fontSize: 13, color: _kTextMuted),
          ),
        ],
      ),
    );
  }
}

// ── Mobile category pill row ─────────────────────────────────────────────────

class _MobileCategoryPillRow extends StatelessWidget {
  final List<CatalogNodeModel> roots;
  final String activeCategoryId;
  final ValueChanged<String> onSelect;

  const _MobileCategoryPillRow({
    required this.roots,
    required this.activeCategoryId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final node in roots) ...[
              _CategoryPill(
                label: node.name,
                isActive: node.id == activeCategoryId,
                onTap: () => onSelect(node.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? _kTextDark : Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isActive ? _kTextDark : _kBorderColor,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : _kTextMid,
          ),
        ),
      ),
    );
  }
}

// ── Right Pane ───────────────────────────────────────────────────────────────

class _RightPane extends ConsumerWidget {
  final String categoryId;
  final String categoryName;
  /// When non-null the user has clicked Browse; chips and cards both switch to
  /// showing this node's children instead of the root category's children.
  final String? browseNodeId;
  final String? activeSubId;
  final ValueChanged<String?> onSubSelected;
  final ValueChanged<String> onBrowseNode;
  final VoidCallback onBack;

  const _RightPane({
    required this.categoryId,
    required this.categoryName,
    required this.browseNodeId,
    required this.activeSubId,
    required this.onSubSelected,
    required this.onBrowseNode,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // effectiveId is the node whose children fill chips + cards.
    // Normally the root category; overridden when user drills in via Browse.
    final effectiveId = browseNodeId ?? categoryId;
    final chipsAsync = ref.watch(catalogNodeChildrenProvider(effectiveId));

    return chipsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load services')),
      data: (chips) {
        return _RightPaneContent(
          // Pass effectiveId so the content widget uses the correct browse context
          // for both the "All" card query and card parentId.
          categoryId: effectiveId,
          categoryName: categoryName,
          chips: chips,
          activeSubId: activeSubId,
          onSubSelected: onSubSelected,
          onBrowseNode: onBrowseNode,
          onBack: onBack,
        );
      },
    );
  }
}

class _RightPaneContent extends ConsumerWidget {
  final String categoryId; // effective browse context (may differ from root)
  final String categoryName;
  final List<CatalogNodeModel> chips;
  final String? activeSubId;
  final ValueChanged<String?> onSubSelected;
  final ValueChanged<String> onBrowseNode;
  final VoidCallback onBack;

  const _RightPaneContent({
    required this.categoryId,
    required this.categoryName,
    required this.chips,
    required this.activeSubId,
    required this.onSubSelected,
    required this.onBrowseNode,
    required this.onBack,
  });

  // The active chip node (null = "All").
  // Returns null when activeSubId is not found in chips so we fall back to
  // "All" instead of silently showing the first chip's content.
  CatalogNodeModel? get _activeSub {
    if (activeSubId == null) return null;
    try {
      return chips.firstWhere((c) => c.id == activeSubId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = _activeSub;

    // Resolve card list provider.
    final cardsAsync = sub == null
        ? ref.watch(catalogNodeChildrenProvider(categoryId))
        : sub.hasChildren
            ? ref.watch(catalogNodeChildrenProvider(sub.id))
            : AsyncValue.data([sub]);

    final cardList = cardsAsync.asData?.value ?? [];
    final resultCount = cardsAsync.isLoading ? null : cardList.length;

    return Container(
      color: _kBgRight,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _rightPad(context), 28, _rightPad(context), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ← Back button.
                  GestureDetector(
                    onTap: onBack,
                    behavior: HitTestBehavior.opaque,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back_rounded,
                              size: 16, color: _kTextMuted),
                          const SizedBox(width: 6),
                          Text(
                            'Back',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _kTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // H1 + result count.
                  _HeaderRow(
                    name: categoryName,
                    subName: sub?.name,
                    count: resultCount,
                  ),
                  const SizedBox(height: 16),

                  // Sub-category chip row.
                  _ChipRow(
                    chips: chips,
                    activeSubId: activeSubId,
                    onSelect: onSubSelected,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),

          // Card grid.
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                _rightPad(context), 0, _rightPad(context), 40),
            sliver: cardsAsync.when(
              loading: () => const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => const SliverToBoxAdapter(
                  child: Center(child: Text('Could not load services'))),
              data: (cards) {
                if (cards.isEmpty) return const _SliverEmpty();
                return SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 340,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _ServiceCard(
                      node: cards[i],
                      parentId: sub?.id ?? categoryId,
                      onBrowse: cards[i].hasChildren
                          ? () => onBrowseNode(cards[i].id)
                          : null,
                    ),
                    childCount: cards.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _rightPad(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= _kBreakpoint) return 36;
    return 16;
  }
}

// Retrieve the category name by reading the first chip's parentName, or fall
// back to the chip's own name when it IS the root (parentName absent).
// This widget reads the root name from the provider instead.
class _HeaderRow extends StatelessWidget {
  final String name;
  final String? subName;
  final int? count;

  const _HeaderRow({required this.name, this.subName, required this.count});

  @override
  Widget build(BuildContext context) {
    final displayName = subName != null ? '$name › $subName' : name;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      children: [
        Text(
          displayName,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _kTextDark,
          ),
        ),
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '($count results)',
              style: GoogleFonts.inter(fontSize: 14, color: _kTextMuted),
            ),
          ),
      ],
    );
  }
}

// ── Sub-category chips ────────────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  final List<CatalogNodeModel> chips;
  final String? activeSubId;
  final ValueChanged<String?> onSelect;

  const _ChipRow({
    required this.chips,
    required this.activeSubId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 18, right: 8),
      child: Row(
        children: [
          _SubChip(
            label: 'All',
            icon: Icons.apps_rounded,
            isActive: activeSubId == null,
            onTap: () => onSelect(null),
          ),
          for (final chip in chips) ...[
            const SizedBox(width: 10),
            _SubChip(
              label: chip.name,
              icon: IconRegistry.resolve(chip.iconKey, chip.name),
              isActive: activeSubId == chip.id,
              onTap: () => onSelect(chip.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SubChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: isActive ? _kTextDark : Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isActive ? _kTextDark : _kBorderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.white : _kTextMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : _kTextMid,
                  height: 1.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends StatefulWidget {
  final CatalogNodeModel node;
  final String parentId;
  /// Non-null only for nodes that have children; tapping the card or Browse
  /// calls this instead of opening a modal, so the explorer drills in-page.
  final VoidCallback? onBrowse;

  const _ServiceCard({
    required this.node,
    required this.parentId,
    this.onBrowse,
  });

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hovered = false;

  /// Called when the whole card is tapped.
  void _cardTap(BuildContext context) {
    if (widget.onBrowse != null) {
      widget.onBrowse!();
    } else {
      openCatalogNode(context, widget.node, parentId: widget.parentId);
    }
  }

  /// Called only by leaf-service action buttons (View Details / Add to cart).
  void _openModal(BuildContext context) {
    openCatalogNode(context, widget.node, parentId: widget.parentId);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _cardTap(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered ? const Color(0xFFFFD21F) : _kBorderColor,
            ),
            boxShadow: _hovered
                ? [
                    const BoxShadow(
                      color: Color(0x40FFD21F),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                      spreadRadius: -20,
                    )
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image area.
              _CardImage(node: node),

              // Body.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (node.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 5),
                        Text(
                          node.description!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _kTextMuted,
                            height: 1.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (node.rating > 0) ...[
                        const SizedBox(height: 8),
                        _RatingRow(
                            rating: node.rating,
                            reviewCount: node.reviewCount),
                      ],
                      const Spacer(),
                      if (node.basePrice != null) ...[
                        Text(
                          'from ₹${node.basePrice!.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else if (node.hasChildren) ...[
                        Text(
                          '${node.childrenCount} options',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _kTextMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // Action row.
                      _ActionRow(
                        node: node,
                        onBrowse: widget.onBrowse,
                        onOpenModal: () => _openModal(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  final CatalogNodeModel node;
  const _CardImage({required this.node});

  @override
  Widget build(BuildContext context) {
    final url = ServiceImageRegistry.resolve(node.imageUrl, node.name);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      child: SizedBox(
        height: 148,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: const Color(0xFFEFEFEF),
            child: Center(
              child: Icon(
                IconRegistry.resolve(node.iconKey, node.name),
                size: 36,
                color: _kTextMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final double rating;
  final int reviewCount;

  const _RatingRow({required this.rating, required this.reviewCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 13, color: AppColors.gold),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _kTextDark,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('|',
              style: GoogleFonts.inter(fontSize: 12, color: _kBorderColor)),
        ),
        Text(
          '$reviewCount reviews',
          style: GoogleFonts.inter(fontSize: 12, color: _kTextMuted),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final CatalogNodeModel node;
  /// Non-null for sub-category cards: drills in-page, never opens a modal.
  final VoidCallback? onBrowse;
  /// Opens the service-detail modal; used for leaf-service buttons only.
  final VoidCallback onOpenModal;

  const _ActionRow({
    required this.node,
    required this.onBrowse,
    required this.onOpenModal,
  });

  @override
  Widget build(BuildContext context) {
    // Sub-category card: single "Browse →" button that stays in the explorer.
    if (onBrowse != null) {
      return _FilledBtn(label: 'Browse →', onTap: onBrowse!);
    }
    // Leaf service card: "View Details" opens the modal.
    return _FilledBtn(label: 'View Details', onTap: onOpenModal);
  }
}


class _FilledBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _FilledBtn({required this.label, required this.onTap});

  @override
  State<_FilledBtn> createState() => _FilledBtnState();
}

class _FilledBtnState extends State<_FilledBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF333333) : _kTextDark,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _SliverEmpty extends StatelessWidget {
  const _SliverEmpty();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _kBorderColor,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Text(
            'No services in this sub-category yet.',
            style: GoogleFonts.inter(fontSize: 14, color: _kTextMuted),
          ),
        ),
      ),
    );
  }
}
