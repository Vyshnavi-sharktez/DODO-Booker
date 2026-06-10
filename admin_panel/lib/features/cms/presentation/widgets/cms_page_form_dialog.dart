import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/cms_providers.dart';
import '../../domain/models/cms_page.dart';

// Default page suggestions — also used by the empty state in cms_pages_page.dart
const kCmsDefaultPages = [
  ('Home', 'home'),
  ('About Us', 'about-us'),
  ('Contact Us', 'contact-us'),
  ('FAQ', 'faq'),
  ('Privacy Policy', 'privacy-policy'),
  ('Terms & Conditions', 'terms-and-conditions'),
];

String _slugify(String title) {
  return title
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class CmsPageFormDialog extends ConsumerStatefulWidget {
  const CmsPageFormDialog({super.key, this.page});

  /// Null = create mode; non-null = edit mode.
  final CmsPage? page;

  @override
  ConsumerState<CmsPageFormDialog> createState() => _CmsPageFormDialogState();
}

class _CmsPageFormDialogState extends ConsumerState<CmsPageFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _slugCtrl;
  late final TextEditingController _contentCtrl;
  late bool _isPublished;
  bool _slugManuallyEdited = false;
  bool _saving = false;

  bool get _isEditing => widget.page != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.page?.pageTitle ?? '');
    _slugCtrl = TextEditingController(text: widget.page?.pageSlug ?? '');
    _contentCtrl =
        TextEditingController(text: widget.page?.pageContent ?? '');
    _isPublished = widget.page?.isPublished ?? false;
    if (_isEditing) _slugManuallyEdited = true; // don't auto-update slug in edit mode
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _slugCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _onTitleChanged(String value) {
    if (!_slugManuallyEdited) {
      final generated = _slugify(value);
      if (_slugCtrl.text != generated) {
        _slugCtrl.text = generated;
        _slugCtrl.selection =
            TextSelection.collapsed(offset: generated.length);
      }
    }
  }

  void _applyDefaultPage(String title, String slug) {
    setState(() {
      _titleCtrl.text = title;
      _slugCtrl.text = slug;
      _slugManuallyEdited = true;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(cmsPagesNotifierProvider.notifier);
      if (_isEditing) {
        await notifier.updatePage(
          widget.page!.id,
          pageSlug: _slugCtrl.text.trim(),
          pageTitle: _titleCtrl.text.trim(),
          pageContent: _contentCtrl.text.trim().isEmpty
              ? null
              : _contentCtrl.text.trim(),
          isPublished: _isPublished,
        );
      } else {
        await notifier.createPage(
          pageSlug: _slugCtrl.text.trim(),
          pageTitle: _titleCtrl.text.trim(),
          pageContent: _contentCtrl.text.trim().isEmpty
              ? null
              : _contentCtrl.text.trim(),
          isPublished: _isPublished,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        final msg = e.toString().contains('duplicate')
            ? 'A page with this slug already exists.'
            : 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
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
            _DialogHeader(
              title: _isEditing
                  ? 'Edit Page'
                  : 'New Page',
              subtitle: _isEditing ? widget.page!.pageTitle : null,
              onClose: () => Navigator.of(context).pop(),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Default page suggestions (create mode only)
                      if (!_isEditing) ...[
                        const Text(
                          'Quick start with a default page',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final (title, slug) in kCmsDefaultPages)
                              _SuggestionChip(
                                label: title,
                                onTap: () => _applyDefaultPage(title, slug),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: AppColors.border),
                        const SizedBox(height: 16),
                      ],

                      // Page Title
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Page Title *',
                          hintText: 'e.g. About Us',
                        ),
                        onChanged: _onTitleChanged,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Page title is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Page Slug
                      TextFormField(
                        controller: _slugCtrl,
                        decoration: InputDecoration(
                          labelText: 'Page Slug *',
                          hintText: 'e.g. about-us',
                          prefixText: '/',
                          suffixIcon: _isEditing
                              ? null
                              : Tooltip(
                                  message: 'Auto-generated from title',
                                  child: const Icon(
                                    Icons.auto_fix_high_rounded,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                        ),
                        onChanged: (v) {
                          _slugManuallyEdited = v.isNotEmpty;
                        },
                        validator: (v) {
                          final val = v?.trim() ?? '';
                          if (val.isEmpty) return 'Slug is required';
                          if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
                              .hasMatch(val)) {
                            return 'Lowercase letters, numbers and hyphens only (e.g. about-us)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Page Content
                      TextFormField(
                        controller: _contentCtrl,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          labelText: 'Page Content',
                          hintText: 'Enter page content…',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Published toggle
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Publish Page',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    _isPublished
                                        ? 'Visible to the public'
                                        : 'Saved as draft',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _isPublished
                                          ? AppColors.success
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPublished,
                              onChanged: (v) =>
                                  setState(() => _isPublished = v),
                              activeThumbColor: AppColors.success,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
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
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isEditing
                                ? Icons.save_rounded
                                : Icons.add_rounded,
                            size: 18,
                          ),
                    label: Text(_isEditing ? 'Save Changes' : 'Create Page'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    this.subtitle,
    required this.onClose,
  });
  final String title;
  final String? subtitle;
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
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.article_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
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

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
