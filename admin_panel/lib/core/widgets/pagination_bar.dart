import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PaginationBar extends StatelessWidget {
  final int totalItems;
  final int currentPage;
  final int pageSize;
  final void Function(int page) onPageChanged;

  const PaginationBar({
    super.key,
    required this.totalItems,
    required this.currentPage,
    required this.onPageChanged,
    this.pageSize = 10,
  });

  int get _totalPages => (totalItems / pageSize).ceil().clamp(1, 999999);

  int get _startItem => totalItems == 0 ? 0 : (currentPage - 1) * pageSize + 1;
  int get _endItem => (currentPage * pageSize).clamp(0, totalItems);

  List<int?> _pages() {
    if (_totalPages <= 7) {
      return List.generate(_totalPages, (i) => i + 1);
    }
    final pages = <int?>[1];
    if (currentPage > 3) pages.add(null); // leading ellipsis
    for (int p = (currentPage - 1).clamp(2, _totalPages - 1);
        p <= (currentPage + 1).clamp(2, _totalPages - 1);
        p++) {
      pages.add(p);
    }
    if (currentPage < _totalPages - 2) pages.add(null); // trailing ellipsis
    pages.add(_totalPages);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    if (totalItems == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $_startItem–$_endItem of $totalItems',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavButton(
                icon: Icons.chevron_left_rounded,
                enabled: currentPage > 1,
                onTap: () => onPageChanged(currentPage - 1),
              ),
              const SizedBox(width: 4),
              ..._pages().map((p) {
                if (p == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary.withAlpha(100))),
                  );
                }
                final selected = p == currentPage;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: selected ? null : () => onPageChanged(p),
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: selected
                            ? null
                            : Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '$p',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 4),
              _NavButton(
                icon: Icons.chevron_right_rounded,
                enabled: currentPage < _totalPages,
                onTap: () => onPageChanged(currentPage + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavButton(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? AppColors.border : AppColors.border.withAlpha(80),
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textSecondary : AppColors.textSecondary.withAlpha(100),
        ),
      ),
    );
  }
}
