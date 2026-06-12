import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../services/wishlist_providers.dart';

class HeartButton extends ConsumerStatefulWidget {
  final String serviceId;
  final bool mini;

  const HeartButton({super.key, required this.serviceId, this.mini = true});

  @override
  ConsumerState<HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends ConsumerState<HeartButton> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final idsAsync = ref.watch(wishlistedIdsProvider);

    return idsAsync.when(
      loading: () => _iconBtn(isWishlisted: false, onTap: null),
      error: (e, _) => _iconBtn(isWishlisted: false, onTap: null),
      data: (ids) {
        final isWishlisted = ids.contains(widget.serviceId);
        return _iconBtn(
          isWishlisted: isWishlisted,
          onTap: _isBusy ? null : () => _toggle(context, ref, isWishlisted),
        );
      },
    );
  }

  Widget _iconBtn({required bool isWishlisted, VoidCallback? onTap}) {
    final size = widget.mini ? 20.0 : 24.0;
    final btnSize = widget.mini ? 36.0 : 40.0;
    return IconButton(
      icon: Icon(
        isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isWishlisted ? const Color(0xFFE91E63) : AppColors.textHint,
        size: size,
      ),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
      splashRadius: btnSize / 2,
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, bool isWishlisted) async {
    if (!ref.read(isAuthenticatedProvider)) {
      final authed = await requireAuth(context, ref);
      if (!context.mounted || !authed) return;
    }

    setState(() => _isBusy = true);
    try {
      final service = ref.read(wishlistServiceProvider);
      if (isWishlisted) {
        await service.removeFromWishlist(widget.serviceId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from wishlist')),
          );
        }
      } else {
        await service.addToWishlist(widget.serviceId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Added to wishlist')),
          );
        }
      }
      ref.invalidate(wishlistedIdsProvider);
      ref.invalidate(wishlistItemsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
