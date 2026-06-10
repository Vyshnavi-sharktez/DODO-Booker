import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/cms_providers.dart';

class SeoSettingDialog extends ConsumerStatefulWidget {
  const SeoSettingDialog({
    super.key,
    required this.pageSlug,
    required this.pageTitle,
  });
  final String pageSlug;
  final String pageTitle;

  @override
  ConsumerState<SeoSettingDialog> createState() => _SeoSettingDialogState();
}

class _SeoSettingDialogState extends ConsumerState<SeoSettingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _metaTitleCtrl = TextEditingController();
  final _metaDescCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();
  final _ogImageCtrl = TextEditingController();
  final _canonicalCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  static const _metaTitleMax = 60;
  static const _metaDescMax = 160;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _metaTitleCtrl.dispose();
    _metaDescCtrl.dispose();
    _keywordsCtrl.dispose();
    _ogImageCtrl.dispose();
    _canonicalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final seo = await ref
          .read(cmsRepositoryProvider)
          .fetchSeoForSlug(widget.pageSlug);
      if (mounted) {
        setState(() {
          _loading = false;
          if (seo != null) {
            _metaTitleCtrl.text = seo.metaTitle ?? '';
            _metaDescCtrl.text = seo.metaDescription ?? '';
            _keywordsCtrl.text = seo.metaKeywords ?? '';
            _ogImageCtrl.text = seo.ogImageUrl ?? '';
            _canonicalCtrl.text = seo.canonicalUrl ?? '';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(cmsRepositoryProvider).upsertSeo(
            pageSlug: widget.pageSlug,
            metaTitle: _metaTitleCtrl.text.trim(),
            metaDescription: _metaDescCtrl.text.trim(),
            metaKeywords: _keywordsCtrl.text.trim(),
            ogImageUrl: _ogImageCtrl.text.trim(),
            canonicalUrl: _canonicalCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save SEO settings: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _SeoDialogHeader(
              pageTitle: widget.pageTitle,
              pageSlug: widget.pageSlug,
              onClose: () => Navigator.of(context).pop(),
            ),

            // Body
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _loadError != null
                      ? _ErrorBody(
                          error: _loadError!,
                          onRetry: () {
                            setState(() {
                              _loading = true;
                              _loadError = null;
                            });
                            _loadExisting();
                          },
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Meta Title
                                _buildCharCountField(
                                  controller: _metaTitleCtrl,
                                  label: 'Meta Title',
                                  hint: 'DODO Booker - Home Services',
                                  maxLength: _metaTitleMax,
                                  helperText:
                                      'Recommended: 50–60 characters',
                                ),
                                const SizedBox(height: 16),

                                // Meta Description
                                _buildCharCountField(
                                  controller: _metaDescCtrl,
                                  label: 'Meta Description',
                                  hint:
                                      'Book trusted home services quickly and easily.',
                                  maxLength: _metaDescMax,
                                  maxLines: 3,
                                  helperText:
                                      'Recommended: 120–160 characters',
                                ),
                                const SizedBox(height: 16),

                                // Meta Keywords
                                TextFormField(
                                  controller: _keywordsCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Meta Keywords',
                                    hintText:
                                        'home services, cleaning, plumbing',
                                    helperText:
                                        'Comma-separated keywords',
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // OG Image URL
                                TextFormField(
                                  controller: _ogImageCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'OG Image URL',
                                    hintText:
                                        'https://example.com/og-image.jpg',
                                    prefixIcon: Icon(
                                      Icons.image_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  validator: (v) {
                                    final val = v?.trim() ?? '';
                                    if (val.isNotEmpty &&
                                        !val.startsWith('http')) {
                                      return 'Must be a valid URL starting with http';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Canonical URL
                                TextFormField(
                                  controller: _canonicalCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Canonical URL',
                                    hintText: 'https://example.com/page',
                                    prefixIcon: Icon(
                                      Icons.link_rounded,
                                      size: 18,
                                    ),
                                  ),
                                  validator: (v) {
                                    final val = v?.trim() ?? '';
                                    if (val.isNotEmpty &&
                                        !val.startsWith('http')) {
                                      return 'Must be a valid URL starting with http';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
            ),

            // Actions
            if (!_loading && _loadError == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Save SEO Settings'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF805AD5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharCountField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    String? helperText,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final len = controller.text.length;
        final over = len > maxLength;
        final counter = '$len / $maxLength';

        return TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helperText,
            counterText: counter,
            counterStyle: TextStyle(
              fontSize: 11,
              color: over ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          validator: (v) {
            if ((v?.length ?? 0) > maxLength) {
              return '$label exceeds $maxLength characters';
            }
            return null;
          },
        );
      },
    );
  }
}

class _SeoDialogHeader extends StatelessWidget {
  const _SeoDialogHeader({
    required this.pageTitle,
    required this.pageSlug,
    required this.onClose,
  });
  final String pageTitle;
  final String pageSlug;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF805AD5).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.manage_search_rounded,
              color: Color(0xFF805AD5),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEO Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        pageTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '/$pageSlug',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
