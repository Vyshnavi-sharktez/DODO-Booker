import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/app_branding_providers.dart';
import '../../domain/models/app_branding_model.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

class AppBrandingPage extends ConsumerWidget {
  const AppBrandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appBrandingNotifierProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () =>
            ref.read(appBrandingNotifierProvider.notifier).refresh(),
      ),
      data: (entries) => _AppBrandingBody(entries: entries),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _AppBrandingBody extends ConsumerStatefulWidget {
  const _AppBrandingBody({required this.entries});

  final List<AppBrandingModel> entries;

  @override
  ConsumerState<_AppBrandingBody> createState() => _AppBrandingBodyState();
}

class _AppBrandingBodyState extends ConsumerState<_AppBrandingBody> {
  final _uploading = <String, bool>{};

  AppBrandingModel _entry(String appId) =>
      ref
          .watch(appBrandingNotifierProvider)
          .valueOrNull
          ?.firstWhere((e) => e.appId == appId,
              orElse: () => widget.entries.firstWhere((e) => e.appId == appId)) ??
      widget.entries.firstWhere((e) => e.appId == appId);

  Future<void> _upload(String appId) async {
    const maxBytes = 2 * 1024 * 1024; // 2 MB

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    if (bytes.lengthInBytes > maxBytes) {
      if (mounted) {
        _showSnack('File too large. Maximum size is 2 MB.', isError: true);
      }
      return;
    }

    final ext = (file.extension ?? '').toLowerCase();
    if (!{'png', 'jpg', 'jpeg', 'webp'}.contains(ext)) {
      if (mounted) {
        _showSnack('Unsupported format. Use PNG, JPG, or WEBP.', isError: true);
      }
      return;
    }

    setState(() => _uploading[appId] = true);
    try {
      await ref.read(appBrandingNotifierProvider.notifier).uploadAndSave(
            appId: appId,
            bytes: bytes,
            extension: ext,
          );
      // Invalidate the sidebar provider so the logo refreshes immediately
      // when the admin panel icon is updated.
      if (appId == 'admin_panel') {
        ref.invalidate(adminPanelBrandingIconProvider);
      }
      if (mounted) {
        _showSnack(appId == 'admin_panel'
            ? 'Icon saved. Sidebar logo will refresh momentarily.'
            : 'Icon saved. The app will display the new logo on next startup or resume.');
      }
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading.remove(appId));
    }
  }

  Future<void> _remove(String appId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove icon?'),
        content: const Text(
            'This clears the stored URL. The default asset will be used instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(appBrandingNotifierProvider.notifier)
          .removeIcon(appId);
      if (appId == 'admin_panel') {
        ref.invalidate(adminPanelBrandingIconProvider);
      }
      if (mounted) _showSnack('Icon removed.');
    } catch (e) {
      if (mounted) _showSnack('Remove failed: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      width: 420,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildInfoBanner(),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 820;
              final ids = ['customer_app', 'vendor_app', 'admin_panel'];
              if (twoCol) {
                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: ids
                      .map((id) => SizedBox(
                            width: (constraints.maxWidth - 20) / 2,
                            child: _AppCard(
                              entry: _entry(id),
                              uploading: _uploading[id] ?? false,
                              onUpload: () => _upload(id),
                              onRemove: () => _remove(id),
                            ),
                          ))
                      .toList(),
                );
              }
              return Column(
                children: ids
                    .map((id) => Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _AppCard(
                            entry: _entry(id),
                            uploading: _uploading[id] ?? false,
                            onUpload: () => _upload(id),
                            onRemove: () => _remove(id),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Page header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.palette_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Branding',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Manage the brand icon for each application',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Info banner ───────────────────────────────────────────────────────────────

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 17, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'All three apps load the brand icon at runtime from this configuration. '
              'Changes are reflected when the app is next opened or resumed — '
              'no rebuild required. '
              'Note: this does not update the installed launcher icon shown on the '
              'device home screen; that is compiled at build time.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── App card ──────────────────────────────────────────────────────────────────

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.entry,
    required this.uploading,
    required this.onUpload,
    required this.onRemove,
  });

  final AppBrandingModel entry;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback onRemove;

  static const _platformLabels = {
    'customer_app': ['Android', 'iOS'],
    'vendor_app': ['Android', 'iOS'],
    'admin_panel': ['Web', 'PWA'],
  };

  static const _appIcons = {
    'customer_app': Icons.smartphone_rounded,
    'vendor_app': Icons.storefront_rounded,
    'admin_panel': Icons.computer_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final platforms = _platformLabels[entry.appId] ?? [];
    final appIcon = _appIcons[entry.appId] ?? Icons.apps_rounded;
    const isImmediate = true; // all apps load the icon at runtime

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(appIcon, platforms, isImmediate),
          _buildCardBody(),
          _buildCardActions(),
        ],
      ),
    );
  }

  Widget _buildCardHeader(
    IconData appIcon,
    List<String> platforms,
    bool isImmediate,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(appIcon, color: AppColors.primary, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 5,
                  children: platforms
                      .map((p) => _PlatformBadge(label: p))
                      .toList(),
                ),
              ],
            ),
          ),
          _EffectBadge(immediate: isImmediate),
        ],
      ),
    );
  }

  Widget _buildCardBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current icon',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          _IconPreview(iconUrl: entry.iconUrl),
          if (entry.updatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last updated: ${DateFormat('d MMM yyyy, HH:mm').format(entry.updatedAt!.toLocal())}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Recommended: 1024 × 1024 px, square, PNG or WEBP. Maximum 2 MB.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: uploading ? null : onUpload,
            icon: uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    entry.hasIcon
                        ? Icons.upload_rounded
                        : Icons.add_photo_alternate_rounded,
                    size: 16,
                  ),
            label: Text(
              uploading
                  ? 'Uploading…'
                  : (entry.hasIcon ? 'Replace Icon' : 'Upload Icon'),
              style: const TextStyle(fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.border,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
          ),
          if (entry.hasIcon) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: uploading ? null : onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Remove', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Icon preview ──────────────────────────────────────────────────────────────

class _IconPreview extends StatelessWidget {
  const _IconPreview({this.iconUrl});
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final url = (iconUrl?.isNotEmpty == true) ? iconUrl : null;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _placeholder(),
              errorBuilder: (_, _, _) => _errorWidget(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => const Center(
        child: Icon(
          Icons.image_outlined,
          size: 36,
          color: AppColors.textSecondary,
        ),
      );

  Widget _errorWidget() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                size: 28, color: AppColors.textSecondary),
            SizedBox(height: 4),
            Text(
              'Failed to load',
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _EffectBadge extends StatelessWidget {
  const _EffectBadge({required this.immediate});
  final bool immediate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: immediate
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        immediate ? 'Live' : 'Rebuild needed',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: immediate ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Failed to load branding configuration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
