import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../domain/models/catalog_service.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/services_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mode enum — controls which data source is searched and tap behavior
// ─────────────────────────────────────────────────────────────────────────────

enum VendorSearchMode { myServices, allServices }

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Search icon button for the Services AppBar.
/// Opens a full-screen search modal scoped to [mode].
class VendorSearchButton extends StatelessWidget {
  final VendorSearchMode mode;

  const VendorSearchButton({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.search_rounded),
      tooltip: mode == VendorSearchMode.myServices
          ? 'Search my services'
          : 'Search all services',
      onPressed: () => _VendorSearchModal.show(context, mode: mode),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen search modal
// ─────────────────────────────────────────────────────────────────────────────

class _VendorSearchModal extends StatefulWidget {
  final VendorSearchMode mode;

  const _VendorSearchModal({required this.mode});

  static Future<void> show(BuildContext context, {required VendorSearchMode mode}) =>
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withAlpha(180),
        useSafeArea: false,
        builder: (_) => _VendorSearchModal(mode: mode),
      );

  @override
  State<_VendorSearchModal> createState() => _VendorSearchModalState();
}

class _VendorSearchModalState extends State<_VendorSearchModal> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTrendingTap(String name) {
    _ctrl.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _focus.requestFocus();
  }

  String get _hintText => widget.mode == VendorSearchMode.myServices
      ? 'Search your services…'
      : 'Search all services…';

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    return Material(
      color: Colors.white,
      child: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(12, padding.top + 8, 12, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.8),
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
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border, width: 0.8),
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
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: _hintText,
                      hintStyle: const TextStyle(
                          fontSize: 14, color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 18, color: AppColors.primary),
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

          // ── Search panel fills remaining height ───────────────────────────
          Expanded(
            child: _VendorSearchPanel(
              ctrl: _ctrl,
              mode: widget.mode,
              onTrendingTap: _onTrendingTap,
              onClose: () => Navigator.pop(context),
            ),
          ),

          if (padding.bottom > 0) SizedBox(height: padding.bottom),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search panel — trending/list section or live results
// ─────────────────────────────────────────────────────────────────────────────

class _VendorSearchPanel extends ConsumerStatefulWidget {
  final TextEditingController ctrl;
  final VendorSearchMode mode;
  final void Function(String) onTrendingTap;
  final VoidCallback onClose;

  const _VendorSearchPanel({
    required this.ctrl,
    required this.mode,
    required this.onTrendingTap,
    required this.onClose,
  });

  @override
  ConsumerState<_VendorSearchPanel> createState() => _VendorSearchPanelState();
}

class _VendorSearchPanelState extends ConsumerState<_VendorSearchPanel> {
  String _lastQuery = '';
  List<CatalogService> _results = [];
  bool _isLoading = false;
  String? _assigningId;
  String? _statusMessage;
  IconData _statusIcon = Icons.check_circle_rounded;
  Color _statusColor = AppColors.success;
  Timer? _timer;
  Timer? _statusTimer;

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
    _statusTimer?.cancel();
    super.dispose();
  }

  void _showStatus(String message, {bool isError = false, bool isInfo = false}) {
    _statusTimer?.cancel();
    setState(() {
      _statusMessage = message;
      _statusIcon = isError
          ? Icons.error_rounded
          : isInfo
              ? Icons.info_rounded
              : Icons.check_circle_rounded;
      _statusColor = isError
          ? AppColors.error
          : isInfo
              ? AppColors.primary
              : AppColors.success;
    });
    _statusTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _statusMessage = null);
    });
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

  Future<void> _onServiceTap(CatalogService service) async {
    if (widget.mode == VendorSearchMode.myServices) {
      // In My Services search, tapping a result just closes the modal.
      widget.onClose();
      return;
    }

    // All Services mode: assign the service.
    if (_assigningId != null) return;

    final user = ref.read(currentVendorUserProvider);
    if (user == null) return;

    final assigned = ref.read(vendorServicesProvider).valueOrNull ?? [];
    if (assigned.any((s) => s.serviceId == service.id)) {
      _showStatus('Already in your services', isInfo: true);
      return;
    }

    // Confirm before assigning.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Add Service',
        message: 'Are you sure you want to add "${service.name}" to your services?',
        confirmLabel: 'Add Service',
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _assigningId = service.id);

    try {
      await ref
          .read(assignServicesProvider.notifier)
          .assign(user.id, [service.id]);
      ref.invalidate(vendorServicesProvider);
      if (!mounted) return;
      _showStatus('"${service.name}" added to your services');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        setState(() => _assigningId = null);
        _showStatus('Could not add service. Please try again.', isError: true);
      }
    }
  }

  void _runSearch(String query) {
    if (!mounted) return;
    final q = query.toLowerCase();

    final List<CatalogService> data;
    if (widget.mode == VendorSearchMode.myServices) {
      final assigned = ref.read(vendorServicesProvider).valueOrNull ?? [];
      data = assigned.map((s) => s.catalog).toList();
    } else {
      data = ref.read(catalogServicesProvider).valueOrNull ?? [];
    }

    final results = data
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.parentName?.toLowerCase().contains(q) ?? false))
        .toList();

    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // catalogServicesProvider only needed in allServices mode.
    if (widget.mode == VendorSearchMode.allServices) {
      ref.watch(catalogServicesProvider);
    }
    // Always watch vendorServicesProvider: My Services list + Add/Added state.
    final assignedIds = (ref.watch(vendorServicesProvider).valueOrNull ?? [])
        .map((s) => s.serviceId)
        .toSet();

    final showList = _lastQuery.length < 2;

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: showList
                ? _buildListSection()
                : _VendorResultsSection(
                    query: _lastQuery,
                    results: _results,
                    isLoading: _isLoading,
                    mode: widget.mode,
                    assigningId: widget.mode == VendorSearchMode.allServices
                        ? _assigningId
                        : null,
                    assignedServiceIds: assignedIds,
                    onServiceTap: _onServiceTap,
                  ),
          ),
          if (_statusMessage != null)
            _StatusBanner(
              message: _statusMessage!,
              icon: _statusIcon,
              color: _statusColor,
            ),
        ],
      ),
    );
  }

  Widget _buildListSection() {
    if (widget.mode == VendorSearchMode.myServices) {
      return _MyServicesListSection(onServiceTap: _onServiceTap);
    }
    return _VendorTrendingSection(onTrendingTap: widget.onTrendingTap);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Services list section — shown when mode = myServices and no query yet
// ─────────────────────────────────────────────────────────────────────────────

class _MyServicesListSection extends ConsumerWidget {
  final void Function(CatalogService) onServiceTap;

  const _MyServicesListSection({required this.onServiceTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedAsync = ref.watch(vendorServicesProvider);

    const header = _PanelHeader(
      icon: Icons.bookmark_rounded,
      label: 'Your Services',
      iconColor: AppColors.primary,
    );

    final inner = assignedAsync.when(
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
      error: (_, _) => const _PanelMessage('Could not load your services'),
      data: (services) {
        if (services.isEmpty) {
          return const _PanelMessage(
              'No services added yet — go to All Services to add some.');
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: services.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 64, color: AppColors.border),
          itemBuilder: (_, i) => _VendorTrendingRow(
            service: services[i].catalog,
            onTap: () => onServiceTap(services[i].catalog),
          ),
        );
      },
    );

    return Column(
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
// Trending section — shown when mode = allServices and no query yet
// ─────────────────────────────────────────────────────────────────────────────

class _VendorTrendingSection extends ConsumerWidget {
  final void Function(String) onTrendingTap;

  const _VendorTrendingSection({required this.onTrendingTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(vendorTrendingServicesProvider);

    const header = _PanelHeader(
      icon: Icons.local_fire_department_rounded,
      label: 'Trending Services',
      iconColor: Color(0xFFF97316),
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
      error: (_, _) =>
          const _PanelMessage('Could not load trending services'),
      data: (services) {
        final visible = services.take(8).toList();
        if (visible.isEmpty) {
          return const _PanelMessage('No trending services right now');
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: visible.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 64, color: AppColors.border),
          itemBuilder: (_, i) => _VendorTrendingRow(
            service: visible[i],
            onTap: () => onTrendingTap(visible[i].name),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: inner),
      ],
    );
  }
}

class _VendorTrendingRow extends StatelessWidget {
  final CatalogService service;
  final VoidCallback onTap;

  const _VendorTrendingRow({required this.service, required this.onTap});

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
                color: AppColors.background,
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
                service.name,
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
// Results section
// ─────────────────────────────────────────────────────────────────────────────

class _VendorResultsSection extends StatelessWidget {
  final String query;
  final List<CatalogService> results;
  final bool isLoading;
  final VendorSearchMode mode;
  final String? assigningId;
  final Set<String> assignedServiceIds;
  final void Function(CatalogService) onServiceTap;

  const _VendorResultsSection({
    required this.query,
    required this.results,
    required this.isLoading,
    required this.mode,
    required this.assigningId,
    required this.assignedServiceIds,
    required this.onServiceTap,
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

    if (isLoading || results.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(height: 1, color: AppColors.border),
          isLoading
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
                ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Scrollbar(
            thumbVisibility: false,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: results.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 62,
                color: AppColors.border,
              ),
              itemBuilder: (_, i) => _VendorResultRow(
                service: results[i],
                query: query,
                mode: mode,
                isAssigning: results[i].id == assigningId,
                isAlreadyAdded: assignedServiceIds.contains(results[i].id),
                onTap: () => onServiceTap(results[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VendorResultRow extends StatefulWidget {
  final CatalogService service;
  final String query;
  final VoidCallback onTap;
  final VendorSearchMode mode;
  final bool isAssigning;
  final bool isAlreadyAdded;

  const _VendorResultRow({
    required this.service,
    required this.query,
    required this.onTap,
    required this.mode,
    required this.isAssigning,
    required this.isAlreadyAdded,
  });

  @override
  State<_VendorResultRow> createState() => _VendorResultRowState();
}

class _VendorResultRowState extends State<_VendorResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final price = '₹${s.basePrice.toStringAsFixed(0)}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: (widget.isAssigning || widget.isAlreadyAdded) ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: _hovered ? const Color(0x0A000000) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Service icon placeholder
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: s.isActive ? AppColors.primaryLight : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.home_repair_service_rounded,
                  size: 20,
                  color: s.isActive ? AppColors.primary : AppColors.textHint,
                ),
              ),
              const SizedBox(width: 12),

              // Name + category + price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                          children: _highlight(s.name, widget.query)),
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
                        if (s.parentName != null) ...[
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children:
                                    _highlight(s.parentName!, widget.query),
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
                        Text(
                          price,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (!s.isActive) ...[
                          const _Dot(),
                          const Text(
                            'Inactive',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              if (widget.mode == VendorSearchMode.allServices)
                _buildAllServicesTrailing()
              else
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllServicesTrailing() {
    if (widget.isAlreadyAdded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.success.withAlpha(90)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 11, color: AppColors.success),
            SizedBox(width: 3),
            Text(
              'Added',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }
    if (widget.isAssigning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 12, color: Colors.white),
          SizedBox(width: 2),
          Text(
            'Add',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status banner — shown at the bottom of the search panel
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;

  const _StatusBanner({
    required this.message,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      color: color,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
// Text highlighting — bold/match behavior matching customer nav_search
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
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
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
