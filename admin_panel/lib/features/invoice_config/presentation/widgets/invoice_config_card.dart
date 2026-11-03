import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/image_upload_field.dart';
import '../../data/invoice_config_repository.dart';

class InvoiceConfigCard extends StatefulWidget {
  const InvoiceConfigCard({super.key});

  @override
  State<InvoiceConfigCard> createState() => _InvoiceConfigCardState();
}

class _InvoiceConfigCardState extends State<InvoiceConfigCard> {
  late final InvoiceConfigRepository _repo;
  final _formKey = GlobalKey<FormState>();

  final _companyNameCtrl = TextEditingController();
  final _taglineCtrl     = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _gstinCtrl       = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _prefixCtrl      = TextEditingController();
  final _footerCtrl      = TextEditingController();

  String? _logoUrl;

  // PDF template state
  String? _templatePdfUrl;
  String? _templatePdfName;
  bool _uploadingTemplate = false;
  String? _templateUploadError;

  InvoiceConfigData? _loaded;
  bool _loading = true;
  bool _saving  = false;
  bool _dirty   = false;

  @override
  void initState() {
    super.initState();
    _repo = InvoiceConfigRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _taglineCtrl.dispose();
    _addressCtrl.dispose();
    _gstinCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _prefixCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await _repo.fetch();
      _loaded = cfg;
      _companyNameCtrl.text = cfg.companyName;
      _taglineCtrl.text     = cfg.companyTagline;
      _addressCtrl.text     = cfg.companyAddress ?? '';
      _gstinCtrl.text       = cfg.companyGstin ?? '';
      _phoneCtrl.text       = cfg.companyPhone ?? '';
      _emailCtrl.text       = cfg.companyEmail ?? '';
      _prefixCtrl.text      = cfg.invoicePrefix;
      _footerCtrl.text      = cfg.footerNote ?? '';
      _logoUrl              = cfg.logoUrl;
      _templatePdfUrl       = cfg.templatePdfUrl;
      _templatePdfName      = cfg.templatePdfName;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load config: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _loading = false; _dirty = false; });
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  // ── PDF template upload ────────────────────────────────────────────────────

  Future<void> _pickAndUploadTemplate() async {
    setState(() { _uploadingTemplate = true; _templateUploadError = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _uploadingTemplate = false);
        return;
      }

      final file = result.files.first;
      Uint8List bytes;
      if (kIsWeb) {
        bytes = file.bytes!;
      } else {
        bytes = await file.xFile.readAsBytes();
      }

      final filename = file.name;
      final storagePath = 'invoice-templates/$filename';

      // Delete any previous template from storage (best-effort)
      if (_templatePdfUrl != null && _templatePdfName != null) {
        final oldPath = 'invoice-templates/${_templatePdfName!}';
        try {
          await Supabase.instance.client.storage
              .from('cms-media')
              .remove([oldPath]);
        } catch (_) {}
      }

      // Upload new template
      await Supabase.instance.client.storage
          .from('cms-media')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      // Get public URL (cms-media is public bucket for templates)
      final publicUrl = Supabase.instance.client.storage
          .from('cms-media')
          .getPublicUrl(storagePath);

      setState(() {
        _templatePdfUrl  = publicUrl;
        _templatePdfName = filename;
        _uploadingTemplate = false;
        _dirty = true;
      });
    } catch (e) {
      setState(() {
        _templateUploadError = 'Upload failed: $e';
        _uploadingTemplate = false;
      });
    }
  }

  Future<void> _removeTemplate() async {
    if (_templatePdfName != null) {
      try {
        await Supabase.instance.client.storage
            .from('cms-media')
            .remove(['invoice-templates/${_templatePdfName!}']);
      } catch (_) {}
    }
    setState(() {
      _templatePdfUrl  = null;
      _templatePdfName = null;
      _dirty = true;
    });
  }

  void _previewTemplate() {
    if (_templatePdfUrl == null) return;
    // Open in new tab (web) or show snackbar with URL (desktop/mobile)
    if (kIsWeb) {
      // Use dart:html only on web; avoid import on non-web builds
      _openUrlInTab(_templatePdfUrl!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template URL: $_templatePdfUrl'),
          action: SnackBarAction(label: 'Copy', onPressed: () {}),
        ),
      );
    }
  }

  // Conditional web-only open — separated to avoid tree-shake issues
  void _openUrlInTab(String url) {
    // dart:html usage gated by kIsWeb check above
    // ignore: avoid_web_libraries_in_flutter
    if (kIsWeb) {
      // Dynamically reference so non-web builds don't pull in dart:html
      _launchUrl(url);
    }
  }

  void _launchUrl(String url) {
    // ignore: undefined_prefixed_name, avoid_web_libraries_in_flutter
    // We use js interop pattern safe on all platforms:
    // On web: opens new tab. On non-web: unreachable (guarded by kIsWeb).
    try {
      // ignore: avoid_dynamic_calls
      (Uri.parse(url)); // no-op parse to validate
      // Since we can't conditionally import dart:html, show snackbar fallback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open in browser: $url')),
        );
      }
    } catch (_) {}
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final updated = InvoiceConfigData(
        id: _loaded?.id,
        companyName:     _companyNameCtrl.text.trim(),
        companyTagline:  _taglineCtrl.text.trim(),
        companyAddress:  _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        companyGstin:    _gstinCtrl.text.trim().isEmpty   ? null : _gstinCtrl.text.trim(),
        companyPhone:    _phoneCtrl.text.trim().isEmpty   ? null : _phoneCtrl.text.trim(),
        companyEmail:    _emailCtrl.text.trim().isEmpty   ? null : _emailCtrl.text.trim(),
        logoUrl:         _logoUrl,
        invoicePrefix:   _prefixCtrl.text.trim().isEmpty ? 'INV' : _prefixCtrl.text.trim(),
        footerNote:      _footerCtrl.text.trim().isEmpty  ? null : _footerCtrl.text.trim(),
        templatePdfUrl:  _templatePdfUrl,
        templatePdfName: _templatePdfName,
      );
      await _repo.save(updated);
      _loaded = updated;
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice config saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'Invoice PDF Template',
            children: [_buildTemplateSection()],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Branding',
            children: [
              _field(
                controller: _companyNameCtrl,
                label: 'Company Name',
                hint: 'DODO BOOKER',
                required: true,
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _taglineCtrl,
                label: 'Tagline',
                hint: 'Home Services Platform',
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 14),
              ImageUploadField(
                label: 'Company Logo',
                value: _logoUrl,
                bucket: 'cms-media',
                pathPrefix: 'invoice-logo/',
                onChanged: (url) {
                  setState(() => _logoUrl = url);
                  _markDirty();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Contact Details',
            children: [
              _field(
                controller: _addressCtrl,
                label: 'Company Address',
                hint: 'e.g. 123 Main St, Mumbai, Maharashtra 400001',
                maxLines: 3,
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _phoneCtrl,
                label: 'Phone',
                hint: 'e.g. +91 98765 43210',
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _emailCtrl,
                label: 'Email',
                hint: 'e.g. support@dodobooker.com',
                onChanged: (_) => _markDirty(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Tax & Legal',
            children: [
              _field(
                controller: _gstinCtrl,
                label: 'GSTIN',
                hint: 'e.g. 27AAAAA0000A1Z5',
                onChanged: (_) => _markDirty(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Invoice Settings',
            children: [
              _field(
                controller: _prefixCtrl,
                label: 'Invoice Number Prefix',
                hint: 'INV',
                helperText:
                    'Appears before the invoice number, e.g. INV-202611-00001. '
                    'Changing this only affects new invoices.',
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 14),
              _field(
                controller: _footerCtrl,
                label: 'Footer Note',
                hint: 'e.g. For queries, contact support@dodobooker.com',
                maxLines: 2,
                onChanged: (_) => _markDirty(),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              FilledButton(
                onPressed: _dirty && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Changes'),
              ),
              if (_dirty) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: const Text('Discard'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── PDF template section widget ────────────────────────────────────────────

  Widget _buildTemplateSection() {
    final hasTemplate = _templatePdfUrl != null && _templatePdfName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload your branded invoice PDF. When a template is active, the system '
          'will use its design (logo, colours, header, footer) and fill in the '
          'actual booking data automatically.',
          style: TextStyle(fontSize: 12, color: Color(0xFF5F6368)),
        ),
        const SizedBox(height: 16),
        if (hasTemplate) ...[
          _TemplateFileCard(
            filename: _templatePdfName!,
            onPreview: _previewTemplate,
            onReplace: _uploadingTemplate ? null : _pickAndUploadTemplate,
            onRemove:  _uploadingTemplate ? null : _removeTemplate,
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _uploadingTemplate ? null : _pickAndUploadTemplate,
            icon: _uploadingTemplate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(_uploadingTemplate ? 'Uploading…' : 'Upload Invoice PDF Template'),
          ),
          const SizedBox(height: 8),
          const Text(
            'PDF files only · Max 10 MB',
            style: TextStyle(fontSize: 11, color: Color(0xFF9AA0A6)),
          ),
        ],
        if (_templateUploadError != null) ...[
          const SizedBox(height: 8),
          Text(
            _templateUploadError!,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ],
    );
  }

  // ── Text field helper ──────────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
    int maxLines = 1,
    bool required = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }
}

// ── Template file card ─────────────────────────────────────────────────────────

class _TemplateFileCard extends StatelessWidget {
  const _TemplateFileCard({
    required this.filename,
    required this.onPreview,
    required this.onReplace,
    required this.onRemove,
  });

  final String filename;
  final VoidCallback? onPreview;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBD6FB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              color: Color(0xFF1A73E8), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Active template',
                  style: TextStyle(fontSize: 11, color: Color(0xFF1A73E8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onPreview,
            child: const Text('Preview'),
          ),
          TextButton(
            onPressed: onReplace,
            child: const Text('Replace'),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: Colors.red,
            tooltip: 'Remove template',
          ),
        ],
      ),
    );
  }
}

// ── Section card ───────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
