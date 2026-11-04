import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_root_categories_providers.dart';
import '../../domain/models/vendor_root_category.dart';
import '../widgets/category_form_dialog.dart';
import '../widgets/category_delete_dialog.dart';

class VendorRootCategoriesPage extends ConsumerStatefulWidget {
  const VendorRootCategoriesPage({super.key});

  @override
  ConsumerState<VendorRootCategoriesPage> createState() =>
      _VendorRootCategoriesPageState();
}

class _VendorRootCategoriesPageState
    extends ConsumerState<VendorRootCategoriesPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VendorRootCategory> _filtered(List<VendorRootCategory> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  void _openCreate(List<VendorRootCategory> all) {
    CategoryFormDialog.show(
      context,
      onSave: ({required name, iconUrl, required sortOrder}) =>
          ref.read(vendorRootCategoriesProvider.notifier).create(
                name: name,
                iconUrl: iconUrl,
                sortOrder: sortOrder,
              ),
    );
  }

  void _openEdit(VendorRootCategory cat) {
    CategoryFormDialog.show(
      context,
      existing: cat,
      onSave: ({required name, iconUrl, required sortOrder}) =>
          ref.read(vendorRootCategoriesProvider.notifier).updateCategory(
                id: cat.id,
                name: name,
                iconUrl: iconUrl,
                sortOrder: sortOrder,
              ),
    );
  }

  void _openDelete(VendorRootCategory cat, List<VendorRootCategory> all) {
    CategoryDeleteDialog.show(
      context,
      category: cat,
      allCategories: all,
      onDeleted: () => ref.invalidate(vendorRootCategoriesProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vendorRootCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            onCreateTap: () => async.whenData((all) => _openCreate(all)),
            searchCtrl: _searchCtrl,
            onSearch: (q) => setState(() => _query = q.trim()),
          ),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: e.toString(),
                onRetry: () => ref.invalidate(vendorRootCategoriesProvider),
              ),
              data: (all) {
                final rows = _filtered(all);
                if (all.isEmpty) return const _EmptyState();
                if (rows.isEmpty) return const _NoResults();
                return _CategoryTable(
                  rows: rows,
                  onEdit: _openEdit,
                  onDelete: (cat) => _openDelete(cat, all),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.onCreateTap,
    required this.searchCtrl,
    required this.onSearch,
  });
  final VoidCallback onCreateTap;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vendor Root Categories',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Manage shared root categories for vendor service discovery',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 240,
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search categories…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: onSearch,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Category'),
          ),
        ],
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _CategoryTable extends StatelessWidget {
  const _CategoryTable({
    required this.rows,
    required this.onEdit,
    required this.onDelete,
  });
  final List<VendorRootCategory> rows;
  final ValueChanged<VendorRootCategory> onEdit;
  final ValueChanged<VendorRootCategory> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Column header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Expanded(flex: 4, child: _ColHeader('Category')),
              Expanded(flex: 2, child: _ColHeader('Created By')),
              SizedBox(
                width: 90,
                child: _ColHeader('Services', align: TextAlign.center),
              ),
              SizedBox(
                width: 80,
                child: _ColHeader('Vendors', align: TextAlign.center),
              ),
              SizedBox(
                width: 90,
                child: _ColHeader('Sort Order', align: TextAlign.center),
              ),
              SizedBox(width: 80, child: _ColHeader('Actions', align: TextAlign.center)),
            ],
          ),
        ),
        // Rows
        Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(10)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                _CategoryRow(
                  category: rows[i],
                  onEdit: onEdit,
                  onDelete: onDelete,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${rows.length} categor${rows.length == 1 ? 'y' : 'ies'}',
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.text, {this.align = TextAlign.left});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Category row ──────────────────────────────────────────────────────────────

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });
  final VendorRootCategory category;
  final ValueChanged<VendorRootCategory> onEdit;
  final ValueChanged<VendorRootCategory> onDelete;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hovered
            ? AppColors.border.withValues(alpha: 0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Name + icon
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _CategoryAvatar(category: cat),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (cat.iconUrl != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            cat.iconUrl!,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Created by
            Expanded(
              flex: 2,
              child: cat.isAdminCreated
                  ? _Badge(
                      label: 'Admin',
                      color: AppColors.accent,
                    )
                  : _Badge(
                      label: 'Vendor',
                      color: AppColors.textSecondary,
                    ),
            ),
            // Service count
            SizedBox(
              width: 90,
              child: Text(
                cat.serviceCount.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: cat.serviceCount > 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: cat.serviceCount > 0
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            // Vendor count
            SizedBox(
              width: 80,
              child: Text(
                cat.vendorCount.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: cat.vendorCount > 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: cat.vendorCount > 0
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            // Sort order
            SizedBox(
              width: 90,
              child: Text(
                cat.sortOrder.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            // Actions
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _IconBtn(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: () => widget.onEdit(cat),
                  ),
                  const SizedBox(width: 4),
                  _IconBtn(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    color: AppColors.error,
                    onTap: () => widget.onDelete(cat),
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

class _CategoryAvatar extends StatelessWidget {
  const _CategoryAvatar({required this.category});
  final VendorRootCategory category;

  @override
  Widget build(BuildContext context) {
    if (category.iconUrl != null && category.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          category.iconUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _Placeholder(name: category.name),
        ),
      );
    }
    return _Placeholder(name: category.name);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color = AppColors.textSecondary,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color color;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 16, color: widget.color),
          ),
        ),
      ),
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.category_outlined,
              size: 56, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'No root categories yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Create the first shared root category using the button above.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text(
            'No categories match your search',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          const Text('Failed to load categories',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(message,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
