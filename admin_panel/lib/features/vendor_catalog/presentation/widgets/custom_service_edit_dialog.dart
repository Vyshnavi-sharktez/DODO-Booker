import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendor_service_requests/data/vendor_service_requests_repository.dart';
import '../../../vendor_service_requests/domain/models/vendor_service_request.dart';

// Vendor app uploads service images to this bucket.
const _kBucket = 'vendor-requests';

class CustomServiceEditDialog extends StatefulWidget {
  const CustomServiceEditDialog({
    super.key,
    required this.service,
    required this.onSaved,
  });

  final VendorServiceRequest service;
  final VoidCallback onSaved;

  static Future<void> show(
    BuildContext context, {
    required VendorServiceRequest service,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CustomServiceEditDialog(service: service, onSaved: onSaved),
    );
  }

  @override
  State<CustomServiceEditDialog> createState() =>
      _CustomServiceEditDialogState();
}

class _CustomServiceEditDialogState extends State<CustomServiceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _imageCtrl;

  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s.serviceName);
    _descCtrl = TextEditingController(text: s.description ?? '');
    _priceCtrl = TextEditingController(
        text: s.activePrice != null
            ? s.activePrice!.toStringAsFixed(0)
            : s.price?.toStringAsFixed(0) ?? '');
    _imageCtrl = TextEditingController(text: s.imageUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  // ── Image upload ──────────────────────────────────────────────────────────

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final mime = const {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
        }[ext] ??
        'image/jpeg';
    final path =
        '${widget.service.vendorId}/${DateTime.now().millisecondsSinceEpoch}.$ext';

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.storage
          .from(_kBucket)
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: mime, upsert: true));
      final url = Supabase.instance.client.storage
          .from(_kBucket)
          .getPublicUrl(path);
      if (mounted) setState(() => _imageCtrl.text = url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo =
          VendorServiceRequestsRepository(Supabase.instance.client);
      await repo.updateCustomService(
        widget.service.id,
        serviceName: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        activePrice: price,
        imageUrl: _imageCtrl.text.trim().isEmpty
            ? null
            : _imageCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service updated.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(child: _buildForm()),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit Service',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  widget.service.serviceName,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Service name ────────────────────────────────────────────
            const _Label('Service Name *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(hintText: 'e.g. AC Repair'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 18),

            // ── Description ─────────────────────────────────────────────
            const _Label('Description'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Short description of the service…'),
            ),
            const SizedBox(height: 18),

            // ── Price ────────────────────────────────────────────────────
            const _Label('Active Price (₹) *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  prefixText: '₹ ', hintText: '0'),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 18),

            // ── Image ────────────────────────────────────────────────────
            const _Label('Service Image'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _imageCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Image URL or upload below'),
                  ),
                ),
                const SizedBox(width: 10),
                _uploading
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: _pickAndUpload,
                        icon: const Icon(Icons.upload_rounded),
                        tooltip: 'Upload image',
                        color: AppColors.primary,
                      ),
              ],
            ),
            // Image preview
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _imageCtrl,
              builder: (context, val, child) {
                final url = val.text.trim();
                if (url.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 48,
                        color: AppColors.border,
                        alignment: Alignment.center,
                        child: const Text('Invalid URL',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                    ),
                  ),
                );
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed:
                _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving || _uploading ? null : _save,
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
