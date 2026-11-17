import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_branding_provider.dart';

/// Displays the customer-app brand logo loaded from Supabase at runtime.
/// Falls back to the bundled asset while loading or when no URL is configured.
/// A changed URL propagates via Realtime immediately, or on the next app resume
/// (whichever comes first) via [App.didChangeAppLifecycleState] → refetchAll.
class BrandingLogo extends ConsumerWidget {
  const BrandingLogo({
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
  });

  final double? height;
  final double? width;
  final BoxFit fit;
  final FilterQuality filterQuality;

  static const _asset = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(customerBrandingIconProvider).valueOrNull;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        height: height,
        width: width,
        fit: fit,
        filterQuality: filterQuality,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _assetImage(),
        errorBuilder: (_, _, _) => _assetImage(),
      );
    }
    return _assetImage();
  }

  Widget _assetImage() => Image.asset(
        _asset,
        height: height,
        width: width,
        fit: fit,
        filterQuality: filterQuality,
      );
}
