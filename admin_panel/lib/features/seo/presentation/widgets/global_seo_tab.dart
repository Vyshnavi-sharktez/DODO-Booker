import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/seo_providers.dart';
import '../../domain/models/seo_global_settings.dart';

/// Tab 1 of the SEO Management page.
///
/// Allows authorised admins to manage brand-wide SEO defaults.
/// All fields are optional — the admin populates them progressively.
/// No production values are pre-seeded or hardcoded.
class GlobalSeoTab extends ConsumerStatefulWidget {
  const GlobalSeoTab({super.key});

  @override
  ConsumerState<GlobalSeoTab> createState() => _GlobalSeoTabState();
}

class _GlobalSeoTabState extends ConsumerState<GlobalSeoTab> {
  final _formKey = GlobalKey<FormState>();

  final _brandNameCtrl = TextEditingController();
  final _brandTaglineCtrl = TextEditingController();
  final _productionDomainCtrl = TextEditingController();
  final _defaultOgImageCtrl = TextEditingController();
  final _titleTemplateCtrl = TextEditingController();
  final _homepageTitleCtrl = TextEditingController();
  final _homepageDescCtrl = TextEditingController();

  bool _loaded = false;
  bool _saving = false;
  String? _loadError;

  static const int _titleMax = 60;
  static const int _descMax = 160;

  @override
  void initState() {
    super.initState();
    _initFromProvider();
  }

  @override
  void dispose() {
    _brandNameCtrl.dispose();
    _brandTaglineCtrl.dispose();
    _productionDomainCtrl.dispose();
    _defaultOgImageCtrl.dispose();
    _titleTemplateCtrl.dispose();
    _homepageTitleCtrl.dispose();
    _homepageDescCtrl.dispose();
    super.dispose();
  }

  void _initFromProvider() {
    final async = ref.read(seoGlobalSettingsProvider);
    async.whenData((settings) => _applySettings(settings));
    if (async is AsyncData) setState(() => _loaded = true);
  }

  void _applySettings(SeoGlobalSettings? settings) {
    if (settings == null) {
      _loaded = true;
      return;
    }
    _brandNameCtrl.text = settings.brandName ?? '';
    _brandTaglineCtrl.text = settings.brandTagline ?? '';
    _productionDomainCtrl.text = settings.productionDomain ?? '';
    _defaultOgImageCtrl.text = settings.defaultOgImageUrl ?? '';
    _titleTemplateCtrl.text = settings.titleTemplate ?? '';
    _homepageTitleCtrl.text = settings.homepageSeoTitle ?? '';
    _homepageDescCtrl.text = settings.homepageSeoDescription ?? '';
    _loaded = true;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(seoRepositoryProvider).upsertGlobalSettings(
            brandName: _brandNameCtrl.text,
            brandTagline: _brandTaglineCtrl.text,
            productionDomain: _productionDomainCtrl.text,
            defaultOgImageUrl: _defaultOgImageCtrl.text,
            titleTemplate: _titleTemplateCtrl.text,
            homepageSeoTitle: _homepageTitleCtrl.text,
            homepageSeoDescription: _homepageDescCtrl.text,
          );
      ref.invalidate(seoGlobalSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Global SEO settings saved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to provider completing after initial build.
    ref.listen<AsyncValue<SeoGlobalSettings?>>(
      seoGlobalSettingsProvider,
      (_, next) {
        next.whenData((s) {
          if (!_loaded) {
            setState(() => _applySettings(s));
          }
        });
        if (next is AsyncError) {
          setState(() {
            _loadError = next.error.toString();
            _loaded = true;
          });
        }
      },
    );

    final settingsAsync = ref.watch(seoGlobalSettingsProvider);

    if (!_loaded && settingsAsync is AsyncLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_loadError!,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _loadError = null;
                  _loaded = false;
                });
                ref.invalidate(seoGlobalSettingsProvider);
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Brand section ────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.business_rounded,
              title: 'Brand Identity',
              description:
                  'Identifies your organisation in search results and social shares.',
            ),
            const SizedBox(height: 16),
            _buildCard(children: [
              _buildTextField(
                controller: _brandNameCtrl,
                label: 'Brand Name',
                hint: 'e.g. DODO Booker',
                maxLength: 100,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _brandTaglineCtrl,
                label: 'Brand Tagline',
                hint: 'e.g. Book home services in minutes',
                maxLength: 150,
              ),
            ]),
            const SizedBox(height: 28),

            // ── Domain section ───────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.language_rounded,
              title: 'Production Domain',
              description:
                  'Required for canonical URLs, sitemaps, and structured data. '
                  'Leave blank until your hosting and domain are confirmed.',
            ),
            const SizedBox(height: 4),
            _DomainWarningBanner(
                isSet: _productionDomainCtrl.text.trim().isNotEmpty),
            const SizedBox(height: 12),
            _buildCard(children: [
              AnimatedBuilder(
                animation: _productionDomainCtrl,
                builder: (_, _) => TextFormField(
                  controller: _productionDomainCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Production Domain',
                    hintText: 'https://yourdomain.com',
                    prefixIcon:
                        Icon(Icons.link_rounded, size: 18),
                    helperText:
                        'Must start with https:// — do not include a trailing slash',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: _validateHttpsUrl,
                ),
              ),
            ]),
            const SizedBox(height: 28),

            // ── Default social image ─────────────────────────────────────────
            _SectionHeader(
              icon: Icons.image_outlined,
              title: 'Default Social / OG Image',
              description:
                  'Fallback image used when sharing DODO pages on social networks. '
                  'Individual catalog nodes can override this.',
            ),
            const SizedBox(height: 16),
            _buildCard(children: [
              TextFormField(
                controller: _defaultOgImageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Default OG Image URL',
                  hintText: 'https://yourdomain.com/og-default.jpg',
                  prefixIcon: Icon(Icons.image_outlined, size: 18),
                  helperText:
                      'Recommended: 1200 × 630 px. Must be publicly accessible.',
                ),
                validator: _validateHttpUrl,
              ),
            ]),
            const SizedBox(height: 28),

            // ── Title template ───────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.title_rounded,
              title: 'Page Title Template',
              description:
                  'Applied to generated SEO page titles. '
                  'Use {page_title} as a placeholder for the individual page name.',
            ),
            const SizedBox(height: 16),
            _buildCard(children: [
              _buildTextField(
                controller: _titleTemplateCtrl,
                label: 'Title Template',
                hint: '{page_title} | DODO Booker',
                maxLength: 100,
                helperText:
                    'The {page_title} placeholder is replaced at generation time',
              ),
            ]),
            const SizedBox(height: 28),

            // ── Homepage SEO ─────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.home_rounded,
              title: 'Homepage SEO',
              description: 'Title and description for the DODO homepage.',
            ),
            const SizedBox(height: 16),
            _buildCard(children: [
              _buildCharCountField(
                controller: _homepageTitleCtrl,
                label: 'Homepage SEO Title',
                hint: 'Book Home Services | DODO Booker',
                maxLength: _titleMax,
                helperText: 'Recommended: 50–60 characters',
              ),
              const SizedBox(height: 16),
              _buildCharCountField(
                controller: _homepageDescCtrl,
                label: 'Homepage Meta Description',
                hint:
                    'Book trusted home services on demand — cleaning, repairs, beauty and more.',
                maxLength: _descMax,
                maxLines: 3,
                helperText: 'Recommended: 120–160 characters',
              ),
            ]),
            const SizedBox(height: 32),

            // ── Actions ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save Global Settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
      ),
      validator: (v) {
        if ((v?.trim().length ?? 0) > maxLength) {
          return '$label exceeds $maxLength characters';
        }
        return null;
      },
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
      builder: (_, _) {
        final len = controller.text.trim().length;
        final over = len > maxLength;
        return TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helperText,
            counterText: '$len / $maxLength',
            counterStyle: TextStyle(
              fontSize: 11,
              color: over ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
              null,
          validator: (v) {
            if ((v?.trim().length ?? 0) > maxLength) {
              return '$label exceeds $maxLength characters';
            }
            return null;
          },
        );
      },
    );
  }

  String? _validateHttpsUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!v.startsWith('https://')) {
      return 'Production domain must start with https://';
    }
    if (v.length < 12) return 'Enter a valid domain (e.g. https://example.com)';
    return null;
  }

  String? _validateHttpUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!v.startsWith('http')) return 'Must be a valid URL starting with http';
    return null;
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DomainWarningBanner extends StatelessWidget {
  const _DomainWarningBanner({required this.isSet});
  final bool isSet;

  @override
  Widget build(BuildContext context) {
    if (isSet) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Production domain not set. '
              'Canonical URLs, sitemaps, and structured data cannot be finalised '
              'until your hosting provider and domain are confirmed.',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}
