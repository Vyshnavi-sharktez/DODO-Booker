import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../search/search_scope.dart';
import '../../features/catalog/models/catalog_node_model.dart';
import '../../features/catalog/providers/catalog_providers.dart';
import '../../features/catalog/utils/catalog_launcher.dart';
import '../../features/home/services/home_providers.dart';
import '../../features/vendor_catalog/models/vcs_vendor_model.dart';
import '../../features/vendor_catalog/providers/vcs_providers.dart';
import '../../features/vendor_custom_service/models/vendor_custom_service_model.dart';
import '../../features/vendor_custom_service/widgets/vendor_custom_service_sheet.dart';
import '../../routes/app_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Inline search bar for desktop/tablet navbar.
/// On focus, opens an overlay showing trending searches or live results.
/// [scope] controls what is searched; defaults to [GlobalSearchScope].
class NavSearchBar extends StatelessWidget {
  const NavSearchBar({super.key, this.scope});
  final SearchScope? scope;

  @override
  Widget build(BuildContext context) => _NavSearchCore(scope: scope);
}

/// Mobile search icon button — opens a full-screen search modal.
/// [scope] is forwarded to the modal so scoped pages retain correct behaviour.
class NavSearchButton extends StatelessWidget {
  const NavSearchButton({super.key, this.scope});
  final SearchScope? scope;

  @override
  Widget build(BuildContext context) {
    return _SmallIconBtn(
      icon: Icons.search_rounded,
      onTap: () => _MobileSearchModal.show(context, scope: scope),
    );
  }
}

/// Opens the mobile full-screen search overlay using the global scope.
/// Called from non-scoped pages; always searches the full catalogue.
Future<void> showMobileSearch(BuildContext context) =>
    _MobileSearchModal.show(context);

// ─────────────────────────────────────────────────────────────────────────────
// Desktop / tablet — inline search with overlay dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _NavSearchCore extends StatefulWidget {
  const _NavSearchCore({this.scope});
  final SearchScope? scope;

  @override
  State<_NavSearchCore> createState() => _NavSearchCoreState();
}

class _NavSearchCoreState extends State<_NavSearchCore> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  // Per-scope result lists tracked for keyboard Enter submission.
  List<CatalogNodeModel> _panelResults = [];
  List<VcsVendorModel> _panelVendorResults = [];
  List<VendorCustomServiceModel> _panelServiceResults = [];

  Timer? _focusCloseTimer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _focus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _focusCloseTimer?.cancel();
        _close();
        _focus.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _focusCloseTimer?.cancel();
    _entry?.remove();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _focusCloseTimer?.cancel();
      _openOverlay();
    } else {
      _focusCloseTimer?.cancel();
      _focusCloseTimer = Timer(const Duration(milliseconds: 250), () {
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

  void _onNodeTap(CatalogNodeModel node) {
    _focusCloseTimer?.cancel();
    _focus.unfocus();
    _close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (node.isLeafBookable) {
        openCatalogNode(context, node);
      } else {
        context.push(AppRoutes.categoryExplorer, extra: {'node': node});
      }
    });
  }

  void _onCustomServiceTap(VendorCustomServiceModel svc) {
    _focusCloseTimer?.cancel();
    _focus.unfocus();
    _close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) VendorCustomServiceSheet.show(context, svc);
    });
  }

  void _onVendorTap(VcsVendorModel vendor) {
    final scope = widget.scope;
    if (scope is! VendorListSearchScope) return;
    _focusCloseTimer?.cancel();
    _focus.unfocus();
    _close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.push(
        '/vendor-catalog/category/${scope.categoryId}/vendor/${vendor.id}',
        extra: {
          'vendorName': vendor.businessName,
          'categoryName': scope.categoryName,
          'vendor': vendor,
        },
      );
    });
  }

  void _onTrendingTap(String name) {
    _ctrl.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _focus.requestFocus();
  }

  void _submitFirst() {
    final scope = widget.scope;
    if (scope is VendorListSearchScope) {
      if (_panelVendorResults.isNotEmpty) _onVendorTap(_panelVendorResults.first);
    } else if (scope is VendorDetailSearchScope) {
      if (_panelServiceResults.isNotEmpty) _onCustomServiceTap(_panelServiceResults.first);
    } else {
      if (_panelResults.isNotEmpty) _onNodeTap(_panelResults.first);
    }
  }

  Widget _buildOverlay(BuildContext ctx) {
    final width = (_link.leaderSize?.width ?? 460).clamp(320.0, 560.0);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focus.unfocus();
              _close();
            },
          ),
        ),
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
              scope: widget.scope,
              compact: true,
              onNodeTap: _onNodeTap,
              onCustomServiceTap: _onCustomServiceTap,
              onVendorTap: _onVendorTap,
              onTrendingTap: _onTrendingTap,
              onClose: _close,
              onResultsChanged: (r) { _panelResults = r; },
              onVendorResultsChanged: (r) { _panelVendorResults = r; },
              onServiceResultsChanged: (r) { _panelServiceResults = r; },
            ),
          ),
        ),
      ],
    );
  }

  String get _hintText {
    final scope = widget.scope;
    if (scope is VendorListSearchScope) {
      return 'Search vendors in ${scope.categoryName}...';
    }
    if (scope is VendorDetailSearchScope) {
      return 'Search services from ${scope.vendorName}...';
    }
    return 'Search for services...';
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
                onSubmitted: (_) => _submitFirst(),
                style: tt.bodySmall
                    ?.copyWith(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _hintText,
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
  final SearchScope? scope;

  /// true → compact mode (overlay with border/shadow, maxHeight 440).
  /// false → expanded mode (fills parent, white background, no border).
  final bool compact;
  final void Function(CatalogNodeModel) onNodeTap;
  final void Function(VendorCustomServiceModel) onCustomServiceTap;
  final void Function(VcsVendorModel) onVendorTap;
  final void Function(String) onTrendingTap;
  final VoidCallback onClose;

  // Per-scope result callbacks used by parent for keyboard Enter handling.
  final ValueChanged<List<CatalogNodeModel>>? onResultsChanged;
  final ValueChanged<List<VcsVendorModel>>? onVendorResultsChanged;
  final ValueChanged<List<VendorCustomServiceModel>>? onServiceResultsChanged;

  const _SearchPanel({
    required this.ctrl,
    required this.compact,
    required this.onNodeTap,
    required this.onCustomServiceTap,
    required this.onVendorTap,
    required this.onTrendingTap,
    required this.onClose,
    this.scope,
    this.onResultsChanged,
    this.onVendorResultsChanged,
    this.onServiceResultsChanged,
  });

  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<_SearchPanel> {
  String _lastQuery = '';

  // Separate typed result lists — no dynamic casting.
  List<CatalogNodeModel> _results = [];
  List<VendorCustomServiceModel> _customResults = [];   // global scope: vendor services
  List<VcsVendorModel> _vendorResults = [];             // vendor-list scope
  List<VendorCustomServiceModel> _serviceResults = [];  // vendor-detail scope

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
      if (mounted) {
        setState(() {
          _results = [];
          _customResults = [];
          _vendorResults = [];
          _serviceResults = [];
          _isLoading = false;
        });
      }
      widget.onResultsChanged?.call([]);
      widget.onVendorResultsChanged?.call([]);
      widget.onServiceResultsChanged?.call([]);
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    _timer = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    final scope = widget.scope ?? const GlobalSearchScope();

    switch (scope) {
      case GlobalSearchScope():
        final fetched = await Future.wait<dynamic>([
          ref.read(catalogServiceProvider).searchNodes(query),
          VendorCustomServiceModel.search(query),
        ]);
        // Discard if a newer query was already issued.
        if (!mounted || _lastQuery != query) return;
        final nodes = fetched[0] as List<CatalogNodeModel>;
        final svcs = fetched[1] as List<VendorCustomServiceModel>;
        setState(() {
          _results = nodes;
          _customResults = svcs;
          _vendorResults = [];
          _serviceResults = [];
          _isLoading = false;
        });
        widget.onResultsChanged?.call(nodes);
        widget.onVendorResultsChanged?.call([]);
        widget.onServiceResultsChanged?.call([]);

      case VendorListSearchScope(categoryId: final catId):
        final allVendors =
            await ref.read(vcsVendorsProvider(catId).future);
        if (!mounted || _lastQuery != query) return;
        final q = query.toLowerCase();
        final filtered = allVendors
            .where((v) => v.businessName.toLowerCase().contains(q))
            .toList();
        setState(() {
          _results = [];
          _customResults = [];
          _vendorResults = filtered;
          _serviceResults = [];
          _isLoading = false;
        });
        widget.onResultsChanged?.call([]);
        widget.onVendorResultsChanged?.call(filtered);
        widget.onServiceResultsChanged?.call([]);

      case VendorDetailSearchScope(vendorId: final vid):
        // categoryId: null matches the exact cache key used by VendorDetailScreen,
        // avoiding a duplicate RPC call.
        final allServices = await ref.read(
          vendorVcsProvider((vendorId: vid, categoryId: null)).future,
        );
        if (!mounted || _lastQuery != query) return;
        final q = query.toLowerCase();
        final filtered = allServices
            .where((s) => s.serviceName.toLowerCase().contains(q))
            .toList();
        setState(() {
          _results = [];
          _customResults = [];
          _vendorResults = [];
          _serviceResults = filtered;
          _isLoading = false;
        });
        widget.onResultsChanged?.call([]);
        widget.onVendorResultsChanged?.call([]);
        widget.onServiceResultsChanged?.call(filtered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showIdle = _lastQuery.length < 2;
    final scope = widget.scope ?? const GlobalSearchScope();

    final Widget section;

    if (showIdle) {
      section = switch (scope) {
        GlobalSearchScope() => _TrendingSection(
            compact: widget.compact,
            onNodeTap: widget.onNodeTap,
            onTrendingTap: widget.onTrendingTap,
          ),
        VendorListSearchScope(
          categoryId: final catId,
          categoryName: final catName,
        ) =>
          _VendorListIdleSection(
            categoryId: catId,
            categoryName: catName,
            compact: widget.compact,
            onTrendingTap: widget.onTrendingTap,
          ),
        VendorDetailSearchScope(
          vendorId: final vid,
          vendorName: final vname,
        ) =>
          _VendorDetailIdleSection(
            vendorId: vid,
            vendorName: vname,
            compact: widget.compact,
            onTrendingTap: widget.onTrendingTap,
          ),
      };
    } else {
      section = switch (scope) {
        GlobalSearchScope() => _ResultsSection(
            compact: widget.compact,
            query: _lastQuery,
            results: _results,
            customResults: _customResults,
            isLoading: _isLoading,
            onNodeTap: widget.onNodeTap,
            onCustomServiceTap: widget.onCustomServiceTap,
          ),
        VendorListSearchScope() => _VendorListResultsSection(
            compact: widget.compact,
            query: _lastQuery,
            vendors: _vendorResults,
            isLoading: _isLoading,
            onVendorTap: widget.onVendorTap,
          ),
        VendorDetailSearchScope() => _ResultsSection(
            compact: widget.compact,
            query: _lastQuery,
            results: const [],
            customResults: _serviceResults,
            isLoading: _isLoading,
            onNodeTap: widget.onNodeTap,
            onCustomServiceTap: widget.onCustomServiceTap,
          ),
      };
    }

    final content = Column(
      mainAxisSize:
          widget.compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.compact) section else Expanded(child: section),
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
// Global idle section — trending services (unchanged behaviour)
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
        if (!compact) {
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 64, color: AppColors.border),
            itemBuilder: (_, i) => _TrendingRow(
              node: visible[i],
              onTap: () => onNodeTap(visible[i]),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible
                .map((n) => _TrendingChip(
                      label: n.name,
                      onTap: () => onNodeTap(n),
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

// ─────────────────────────────────────────────────────────────────────────────
// Vendor-list idle section — shows top vendors from the already-cached list
// ─────────────────────────────────────────────────────────────────────────────

class _VendorListIdleSection extends ConsumerWidget {
  final String categoryId;
  final String categoryName;
  final bool compact;
  final void Function(String) onTrendingTap;

  const _VendorListIdleSection({
    required this.categoryId,
    required this.categoryName,
    required this.compact,
    required this.onTrendingTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vcsVendorsProvider(categoryId));

    final header = _PanelHeader(
      icon: Icons.storefront_rounded,
      label: 'Vendors in $categoryName',
      iconColor: AppColors.textSecondary,
    );

    final inner = vendorsAsync.when(
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
      error: (_, _) => const _PanelMessage('Could not load vendors'),
      data: (vendors) {
        final visible = vendors.take(8).toList();
        if (visible.isEmpty) {
          return const _PanelMessage('No vendors in this category');
        }
        if (!compact) {
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 64, color: AppColors.border),
            itemBuilder: (_, i) => _GenericTrendingRow(
              label: visible[i].businessName,
              icon: Icons.storefront_rounded,
              onTap: () => onTrendingTap(visible[i].businessName),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible
                .map((v) => _TrendingChip(
                      label: v.businessName,
                      onTap: () => onTrendingTap(v.businessName),
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

// ─────────────────────────────────────────────────────────────────────────────
// Vendor-detail idle section — shows top services from the already-cached list
// ─────────────────────────────────────────────────────────────────────────────

class _VendorDetailIdleSection extends ConsumerWidget {
  final String vendorId;
  final String vendorName;
  final bool compact;
  final void Function(String) onTrendingTap;

  const _VendorDetailIdleSection({
    required this.vendorId,
    required this.vendorName,
    required this.compact,
    required this.onTrendingTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // categoryId: null matches the exact cache key used by VendorDetailScreen.
    final servicesAsync = ref.watch(
      vendorVcsProvider((vendorId: vendorId, categoryId: null)),
    );

    final header = _PanelHeader(
      icon: Icons.home_repair_service_rounded,
      label: 'Services from $vendorName',
      iconColor: AppColors.textSecondary,
    );

    final inner = servicesAsync.when(
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
      error: (_, _) => const _PanelMessage('Could not load services'),
      data: (services) {
        final visible = services.take(8).toList();
        if (visible.isEmpty) {
          return const _PanelMessage('No services available');
        }
        if (!compact) {
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 64, color: AppColors.border),
            itemBuilder: (_, i) => _GenericTrendingRow(
              label: visible[i].serviceName,
              icon: Icons.home_repair_service_rounded,
              onTap: () => onTrendingTap(visible[i].serviceName),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible
                .map((s) => _TrendingChip(
                      label: s.serviceName,
                      onTap: () => onTrendingTap(s.serviceName),
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

// ─────────────────────────────────────────────────────────────────────────────
// Results section — global scope (catalog nodes + vendor services)
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final bool compact;
  final String query;
  final List<CatalogNodeModel> results;
  final List<VendorCustomServiceModel> customResults;
  final bool isLoading;
  final void Function(CatalogNodeModel) onNodeTap;
  final void Function(VendorCustomServiceModel) onCustomServiceTap;

  const _ResultsSection({
    required this.compact,
    required this.query,
    required this.results,
    required this.customResults,
    required this.isLoading,
    required this.onNodeTap,
    required this.onCustomServiceTap,
  });

  @override
  Widget build(BuildContext context) {
    final header = _PanelHeader(
      icon: Icons.search_rounded,
      label: isLoading
          ? 'Searching...'
          : results.isEmpty && customResults.isEmpty
              ? 'No results for "$query"'
              : 'Results for "$query"',
      iconColor: AppColors.textSecondary,
    );

    if (isLoading || (results.isEmpty && customResults.isEmpty)) {
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

    final items = <Widget>[
      for (int i = 0; i < results.length; i++) ...[
        if (i > 0)
          const Divider(height: 1, indent: 62, color: AppColors.border),
        _ResultRow(
          node: results[i],
          query: query,
          onTap: () => onNodeTap(results[i]),
        ),
      ],
      for (int i = 0; i < customResults.length; i++) ...[
        if (i > 0 || results.isNotEmpty)
          const Divider(height: 1, indent: 62, color: AppColors.border),
        _VendorServiceRow(
          service: customResults[i],
          query: query,
          onTap: () => onCustomServiceTap(customResults[i]),
        ),
      ],
    ];
    final list = Scrollbar(
      thumbVisibility: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: items,
      ),
    );

    if (compact) {
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

// ─────────────────────────────────────────────────────────────────────────────
// Vendor-list results section
// ─────────────────────────────────────────────────────────────────────────────

class _VendorListResultsSection extends StatelessWidget {
  final bool compact;
  final String query;
  final List<VcsVendorModel> vendors;
  final bool isLoading;
  final void Function(VcsVendorModel) onVendorTap;

  const _VendorListResultsSection({
    required this.compact,
    required this.query,
    required this.vendors,
    required this.isLoading,
    required this.onVendorTap,
  });

  @override
  Widget build(BuildContext context) {
    final header = _PanelHeader(
      icon: Icons.storefront_rounded,
      label: isLoading
          ? 'Searching vendors...'
          : vendors.isEmpty
              ? 'No vendors match "$query"'
              : 'Vendors for "$query"',
      iconColor: AppColors.textSecondary,
    );

    if (isLoading || vendors.isEmpty) {
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
                      'No vendors match "$query"',
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

    final items = <Widget>[
      for (int i = 0; i < vendors.length; i++) ...[
        if (i > 0)
          const Divider(height: 1, indent: 62, color: AppColors.border),
        _VendorRow(
          vendor: vendors[i],
          query: query,
          onTap: () => onVendorTap(vendors[i]),
        ),
      ],
    ];
    final list = Scrollbar(
      thumbVisibility: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: items,
      ),
    );

    if (compact) {
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

// ─────────────────────────────────────────────────────────────────────────────
// Result rows
// ─────────────────────────────────────────────────────────────────────────────

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
        ? '₹${(node.finalPrice ?? node.basePrice)!.toStringAsFixed(0)}'
        : null;
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
                    const Text(
                      'DODO Service',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (price != null) ...[
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
              ],
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

class _VendorServiceRow extends StatefulWidget {
  final VendorCustomServiceModel service;
  final String query;
  final VoidCallback onTap;

  const _VendorServiceRow({
    required this.service,
    required this.query,
    required this.onTap,
  });

  @override
  State<_VendorServiceRow> createState() => _VendorServiceRowState();
}

class _VendorServiceRowState extends State<_VendorServiceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: _hovered ? const Color(0x0A000000) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: svc.imageUrl != null
                    ? Image.network(
                        svc.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const _ImagePlaceholder(size: 44),
                      )
                    : const _ImagePlaceholder(size: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: _highlight(svc.serviceName, widget.query),
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
                    Text(
                      svc.vendorName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                svc.formattedPrice,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.open_in_new_rounded,
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

/// Result row for vendor-list scope search results.
class _VendorRow extends StatefulWidget {
  final VcsVendorModel vendor;
  final String query;
  final VoidCallback onTap;

  const _VendorRow({
    required this.vendor,
    required this.query,
    required this.onTap,
  });

  @override
  State<_VendorRow> createState() => _VendorRowState();
}

class _VendorRowState extends State<_VendorRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.vendor;
    final rating = v.rating?.toStringAsFixed(1);
    final priceLabel =
        v.minServicePrice != null ? 'From ₹${v.minServicePrice!.toInt()}' : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: _hovered ? const Color(0x0A000000) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceVariant,
                backgroundImage: v.profileImageUrl != null
                    ? NetworkImage(v.profileImageUrl!)
                    : null,
                child: v.profileImageUrl == null
                    ? const Icon(Icons.storefront_rounded,
                        size: 20, color: AppColors.textHint)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: _highlight(v.businessName, widget.query),
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
                        if (rating != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 11, color: AppColors.gold),
                          const SizedBox(width: 3),
                          Text(
                            rating,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          '${v.serviceCount} service${v.serviceCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (priceLabel != null) ...[
                Text(
                  priceLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(
                Icons.arrow_forward_ios_rounded,
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
// Trending / idle chips and rows
// ─────────────────────────────────────────────────────────────────────────────

class _TrendingChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _TrendingChip({required this.label, required this.onTap});

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
                  widget.label,
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

/// Mobile trending row for the global idle section — full-width list item.
class _TrendingRow extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _TrendingRow({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.trending_up_rounded,
                size: 16,
                color: Color(0xFFF97316),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic mobile idle row for vendor and service idle sections.
class _GenericTrendingRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GenericTrendingRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: AppColors.textHint,
            ),
          ],
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
  final BuildContext parentContext;
  final SearchScope? scope;

  const _MobileSearchModal({required this.parentContext, this.scope});

  static Future<void> show(BuildContext context, {SearchScope? scope}) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(180),
      useSafeArea: false,
      builder: (_) =>
          _MobileSearchModal(parentContext: context, scope: scope),
    );
  }

  @override
  State<_MobileSearchModal> createState() => _MobileSearchModalState();
}

class _MobileSearchModalState extends State<_MobileSearchModal> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<CatalogNodeModel> _panelResults = [];
  List<VcsVendorModel> _panelVendorResults = [];
  List<VendorCustomServiceModel> _panelServiceResults = [];

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
    final parentCtx = widget.parentContext;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!parentCtx.mounted) return;
      if (node.isLeafBookable) {
        openCatalogNode(parentCtx, node);
      } else {
        parentCtx.push(AppRoutes.categoryExplorer, extra: {'node': node});
      }
    });
  }

  void _onCustomServiceTap(VendorCustomServiceModel svc) {
    final parentCtx = widget.parentContext;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (parentCtx.mounted) VendorCustomServiceSheet.show(parentCtx, svc);
    });
  }

  void _onVendorTap(VcsVendorModel vendor) {
    final scope = widget.scope;
    if (scope is! VendorListSearchScope) return;
    final parentCtx = widget.parentContext;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!parentCtx.mounted) return;
      parentCtx.push(
        '/vendor-catalog/category/${scope.categoryId}/vendor/${vendor.id}',
        extra: {
          'vendorName': vendor.businessName,
          'categoryName': scope.categoryName,
          'vendor': vendor,
        },
      );
    });
  }

  void _onTrendingTap(String name) {
    _ctrl.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _focus.requestFocus();
  }

  void _submitFirst() {
    final scope = widget.scope;
    if (scope is VendorListSearchScope) {
      if (_panelVendorResults.isNotEmpty) _onVendorTap(_panelVendorResults.first);
    } else if (scope is VendorDetailSearchScope) {
      if (_panelServiceResults.isNotEmpty) _onCustomServiceTap(_panelServiceResults.first);
    } else {
      if (_panelResults.isNotEmpty) _onNodeTap(_panelResults.first);
    }
  }

  String get _hintText {
    final scope = widget.scope;
    if (scope is VendorListSearchScope) {
      return 'Search vendors in ${scope.categoryName}...';
    }
    if (scope is VendorDetailSearchScope) {
      return 'Search services from ${scope.vendorName}...';
    }
    return 'Search for services...';
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
            padding: EdgeInsets.fromLTRB(
                12, padding.top + 8, 12, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                    color: AppColors.border, width: 0.8),
              ),
            ),
            child: Row(
              children: [
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
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submitFirst(),
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: _hintText,
                      hintStyle: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 18, color: AppColors.gold),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _ctrl,
                        builder: (_, val, _) => val.text.isEmpty
                            ? const SizedBox.shrink()
                            : GestureDetector(
                                onTap: _ctrl.clear,
                                child: const Icon(Icons.clear_rounded,
                                    size: 16, color: AppColors.textHint),
                              ),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Results panel
          Expanded(
            child: _SearchPanel(
              ctrl: _ctrl,
              scope: widget.scope,
              compact: false,
              onNodeTap: _onNodeTap,
              onCustomServiceTap: _onCustomServiceTap,
              onVendorTap: _onVendorTap,
              onTrendingTap: _onTrendingTap,
              onClose: () => Navigator.pop(context),
              onResultsChanged: (r) { _panelResults = r; },
              onVendorResultsChanged: (r) { _panelVendorResults = r; },
              onServiceResultsChanged: (r) { _panelServiceResults = r; },
            ),
          ),

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
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
