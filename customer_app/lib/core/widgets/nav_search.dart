import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../../features/catalog/models/catalog_node_model.dart';
import '../../features/catalog/providers/catalog_providers.dart';
import '../../features/catalog/utils/catalog_launcher.dart';
import '../../features/home/services/home_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Inline search bar for desktop/tablet navbar.
/// On focus, opens an overlay showing trending searches or live results.
class NavSearchBar extends StatelessWidget {
  const NavSearchBar({super.key});

  @override
  Widget build(BuildContext context) => const _NavSearchCore();
}

/// Mobile search icon button — opens a full-screen search modal.
class NavSearchButton extends StatelessWidget {
  const NavSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SmallIconBtn(
      icon: Icons.search_rounded,
      onTap: () => _MobileSearchModal.show(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop / tablet — inline search with overlay dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _NavSearchCore extends StatefulWidget {
  const _NavSearchCore();

  @override
  State<_NavSearchCore> createState() => _NavSearchCoreState();
}

class _NavSearchCoreState extends State<_NavSearchCore> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _focus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _close();
        _focus.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _entry?.remove();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _openOverlay();
    } else {
      // Delay so result taps can fire before the overlay disappears.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_focus.hasFocus && mounted) _close();
      });
    }
  }

  void _openOverlay() {
    if (_open) return;
    final entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: false).insert(entry);
    _entry = entry;
    if (mounted) setState(() => _open = true);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _ctrl.clear();
    if (mounted) setState(() => _open = false);
  }

  // Called from panel when a node is tapped.
  // Uses State.context (stable as long as the nav bar is mounted).
  void _onNodeTap(CatalogNodeModel node) {
    _close();
    openCatalogNode(context, node);
  }

  // Called from trending chip — populate the text field with the node name.
  void _onTrendingTap(String name) {
    _ctrl.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    // Keep the field focused so the overlay stays open showing results.
    _focus.requestFocus();
  }

  Widget _buildOverlay(BuildContext ctx) {
    final width = (_link.leaderSize?.width ?? 460).clamp(320.0, 560.0);
    return Stack(
      children: [
        // Full-screen barrier — tap outside to close.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focus.unfocus();
              _close();
            },
          ),
        ),
        // Dropdown panel anchored to the bottom of the search bar.
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: SizedBox(
            width: width,
            child: _SearchPanel(
              ctrl: _ctrl,
              compact: true,
              onNodeTap: _onNodeTap,
              onTrendingTap: _onTrendingTap,
              onClose: _close,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return CompositedTransformTarget(
      link: _link,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 44,
        decoration: BoxDecoration(
          color: _open ? Colors.white : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color:
                _open ? AppColors.gold.withAlpha(153) : AppColors.border,
            width: _open ? 1.5 : 0.8,
          ),
          boxShadow: _open
              ? [
                  BoxShadow(
                      color: AppColors.gold.withAlpha(26), blurRadius: 12)
                ]
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              size: 18,
              color: _open ? AppColors.gold : AppColors.textHint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {},
                style: tt.bodySmall
                    ?.copyWith(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search for services...',
                  hintStyle: tt.bodySmall
                      ?.copyWith(color: AppColors.textHint, fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, val, _) => val.text.isEmpty
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: _ctrl.clear,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.clear_rounded,
                            size: 16, color: AppColors.textHint),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search panel — shared between desktop overlay and mobile modal
// ─────────────────────────────────────────────────────────────────────────────

class _SearchPanel extends ConsumerStatefulWidget {
  final TextEditingController ctrl;

  /// true → compact mode (overlay with border/shadow, maxHeight 440).
  /// false → expanded mode (fills parent, white background, no border).
  final bool compact;
  final void Function(CatalogNodeModel) onNodeTap;
  final void Function(String) onTrendingTap;
  final VoidCallback onClose;

  const _SearchPanel({
    required this.ctrl,
    required this.compact,
    required this.onNodeTap,
    required this.onTrendingTap,
    required this.onClose,
  });

  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<_SearchPanel> {
  String _lastQuery = '';
  List<CatalogNodeModel> _results = [];
  bool _isLoading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lastQuery = widget.ctrl.text.trim();
    widget.ctrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onQueryChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = widget.ctrl.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    _timer?.cancel();

    if (q.length < 2) {
      if (mounted) setState(() { _results = []; _isLoading = false; });
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    _timer = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    final results =
        await ref.read(catalogServiceProvider).searchNodes(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTrending = _lastQuery.length < 2;
    final content = Column(
      mainAxisSize:
          widget.compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTrending)
          _TrendingSection(
            compact: widget.compact,
            onNodeTap: widget.onNodeTap,
            onTrendingTap: widget.onTrendingTap,
          )
        else
          _ResultsSection(
            compact: widget.compact,
            query: _lastQuery,
            results: _results,
            isLoading: _isLoading,
            onNodeTap: widget.onNodeTap,
          ),
      ],
    );

    if (!widget.compact) {
      return Container(color: Colors.white, child: content);
    }

    return Material(
      elevation: 20,
      shadowColor: Colors.black.withAlpha(30),
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: content,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trending section
// ─────────────────────────────────────────────────────────────────────────────

class _TrendingSection extends ConsumerWidget {
  final bool compact;
  final void Function(CatalogNodeModel) onNodeTap;
  final void Function(String) onTrendingTap;

  const _TrendingSection({
    required this.compact,
    required this.onNodeTap,
    required this.onTrendingTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingServicesProvider);

    final header = _PanelHeader(
      icon: Icons.local_fire_department_rounded,
      label: 'Trending Searches',
      iconColor: const Color(0xFFF97316),
    );

    final inner = trendingAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.textHint),
          ),
        ),
      ),
      error: (_, _) => const _PanelMessage('Could not load trending services'),
      data: (nodes) {
        final visible =
            nodes.where((n) => n.isBookable).take(8).toList();
        if (visible.isEmpty) {
          return const _PanelMessage('No trending services right now');
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible
                .map((n) => _TrendingChip(
                      node: n,
                      onTap: () => onTrendingTap(n.name),
                    ))
                .toList(),
          ),
        );
      },
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(height: 1, color: AppColors.border),
          Flexible(child: inner),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: inner),
      ],
    );
  }
}

class _TrendingChip extends StatefulWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _TrendingChip({required this.node, required this.onTap});

  @override
  State<_TrendingChip> createState() => _TrendingChipState();
}

class _TrendingChipState extends State<_TrendingChip> {
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
          duration: const Duration(milliseconds: 130),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(130)
                  : AppColors.border,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.trending_up_rounded,
                size: 13,
                color: _hovered ? AppColors.gold : AppColors.textHint,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  widget.node.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _hovered
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results section
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final bool compact;
  final String query;
  final List<CatalogNodeModel> results;
  final bool isLoading;
  final void Function(CatalogNodeModel) onNodeTap;

  const _ResultsSection({
    required this.compact,
    required this.query,
    required this.results,
    required this.isLoading,
    required this.onNodeTap,
  });

  @override
  Widget build(BuildContext context) {
    final header = _PanelHeader(
      icon: Icons.search_rounded,
      label: isLoading
          ? 'Searching…'
          : results.isEmpty
              ? 'No results for "$query"'
              : 'Results for "$query"',
      iconColor: AppColors.textSecondary,
    );

    // Loading and empty states are small — no scroll container needed.
    if (isLoading || results.isEmpty) {
      final body = isLoading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textHint),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded,
                        size: 32, color: AppColors.textHint),
                    const SizedBox(height: 8),
                    Text(
                      'No services match "$query"',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(height: 1, color: AppColors.border),
          body,
        ],
      );
    }

    // Scrollable results list — shrinkWrap off so the ListView can scroll.
    final list = Scrollbar(
      thumbVisibility: false,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: results.length,
        separatorBuilder: (_, $i) => const Divider(
          height: 1,
          indent: 62,
          color: AppColors.border,
        ),
        itemBuilder: (ctx, i) => _ResultRow(
          node: results[i],
          query: query,
          onTap: () => onNodeTap(results[i]),
        ),
      ),
    );

    if (compact) {
      // ConstrainedBox gives the ListView a bounded height so it scrolls
      // instead of overflowing. 360 leaves room for the header inside the
      // 440px panel cap set on _SearchPanel.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(height: 1, color: AppColors.border),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: list,
          ),
        ],
      );
    }

    // Mobile modal — Expanded provides the bounded height from the parent.
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: list),
      ],
    );
  }
}

class _ResultRow extends StatefulWidget {
  final CatalogNodeModel node;
  final String query;
  final VoidCallback onTap;

  const _ResultRow(
      {required this.node, required this.query, required this.onTap});

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final price = node.basePrice != null
        ? '₹${node.basePrice!.toStringAsFixed(0)}'
        : null;
    final hasRating = node.rating > 0 && node.reviewCount > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: _hovered
              ? const Color(0x0A000000)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: node.imageUrl != null
                    ? Image.network(
                        node.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const _ImagePlaceholder(size: 44),
                      )
                    : const _ImagePlaceholder(size: 44),
              ),
              const SizedBox(width: 12),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children:
                            _highlight(node.name, widget.query),
                      ),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (node.parentName != null) ...[
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children: _highlight(
                                  node.parentName!,
                                  widget.query,
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const _Dot(),
                        ],
                        if (hasRating) ...[
                          const Icon(Icons.star_rounded,
                              size: 11,
                              color: Color(0xFFF59E0B)),
                          const SizedBox(width: 2),
                          Text(
                            node.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const _Dot(),
                        ],
                        if (price != null)
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Icon(
                node.hasChildren
                    ? Icons.arrow_forward_ios_rounded
                    : Icons.open_in_new_rounded,
                size: 12,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text highlighting
// ─────────────────────────────────────────────────────────────────────────────

List<InlineSpan> _highlight(String text, String query) {
  if (query.isEmpty) return [TextSpan(text: text)];
  final lText = text.toLowerCase();
  final lQuery = query.toLowerCase();
  final spans = <InlineSpan>[];
  int start = 0;
  while (start < text.length) {
    final idx = lText.indexOf(lQuery, start);
    if (idx == -1) {
      spans.add(TextSpan(text: text.substring(start)));
      break;
    }
    if (idx > start) {
      spans.add(TextSpan(text: text.substring(start, idx)));
    }
    spans.add(TextSpan(
      text: text.substring(idx, idx + query.length),
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    ));
    start = idx + query.length;
  }
  return spans;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile full-screen search modal
// ─────────────────────────────────────────────────────────────────────────────

class _MobileSearchModal extends StatefulWidget {
  const _MobileSearchModal();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(180),
      useSafeArea: false,
      builder: (_) => const _MobileSearchModal(),
    );
  }

  @override
  State<_MobileSearchModal> createState() => _MobileSearchModalState();
}

class _MobileSearchModalState extends State<_MobileSearchModal> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onNodeTap(CatalogNodeModel node) {
    Navigator.pop(context);
    openCatalogNode(context, node);
  }

  void _onTrendingTap(String name) {
    _ctrl.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    return Material(
      color: Colors.white,
      child: Column(
        children: [
          // Top bar
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(
                12, padding.top + 8, 12, 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: AppColors.border, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                // Back button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.border, width: 0.8),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        size: 20, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 10),
                // Search input
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.gold.withAlpha(153),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        const Icon(Icons.search_rounded,
                            size: 18, color: AppColors.gold),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) {},
                            style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Search for services...',
                              hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textHint),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _ctrl,
                          builder: (_, val, _) => val.text.isEmpty
                              ? const SizedBox.shrink()
                              : GestureDetector(
                                  onTap: _ctrl.clear,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Icon(Icons.clear_rounded,
                                        size: 16,
                                        color: AppColors.textHint),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Results panel — fills remaining height
          Expanded(
            child: _SearchPanel(
              ctrl: _ctrl,
              compact: false,
              onNodeTap: _onNodeTap,
              onTrendingTap: _onTrendingTap,
              onClose: () => Navigator.pop(context),
            ),
          ),

          // Bottom safe area
          if (padding.bottom > 0) SizedBox(height: padding.bottom),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _PanelHeader({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  final String text;
  const _PanelMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final double size;
  const _ImagePlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.home_repair_service_rounded,
          size: 20, color: AppColors.textHint),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
            color: AppColors.textHint, shape: BoxShape.circle),
      ),
    );
  }
}

class _SmallIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SmallIconBtn({required this.icon, required this.onTap});

  @override
  State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
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
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.goldLight
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(100)
                  : AppColors.border,
              width: 0.8,
            ),
          ),
          child:
              Icon(widget.icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
