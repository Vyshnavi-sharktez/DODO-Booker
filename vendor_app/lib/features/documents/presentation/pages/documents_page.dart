import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/models/vendor_document.dart';
import '../providers/documents_provider.dart';
import '../utils/document_file_picker.dart'
    if (dart.library.html) '../utils/document_file_picker_web.dart'
    if (dart.library.io) '../utils/document_file_picker_mobile.dart';
import '../widgets/document_tile.dart';
import '../widgets/upload_document_dialog.dart';

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  final _replacingTypes = <String>{};

  Future<void> _showUploadDialog(
    BuildContext context,
    List<DocumentTypeModel> availableTypes,
  ) async {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final uploaded = await showDialog<bool>(
      context: context,
      builder: (_) => UploadDocumentDialog(
        availableTypes: availableTypes,
        onUpload: (documentType, bytes, contentType, customDocumentName) =>
            ref.read(uploadDocumentUseCaseProvider)(
          vendorId: vendor.id,
          documentType: documentType,
          bytes: bytes,
          contentType: contentType,
          customDocumentName: customDocumentName,
        ),
      ),
    );

    if (uploaded == true) {
      ref.invalidate(vendorDocumentsProvider);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Document uploaded successfully')),
        );
      }
    }
  }

  Future<void> _replace(VendorDocument doc) async {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    debugPrint('[FILE_PICKER] Replace clicked — docType: ${doc.documentType}');
    PickedDocument? picked;
    try {
      debugPrint('[FILE_PICKER] Opening picker…');
      picked = await pickDocumentFile();
      debugPrint(
        '[FILE_PICKER] Picker returned: ${picked == null ? "null (cancelled)" : picked.name}',
      );
    } catch (e) {
      debugPrint('[FILE_PICKER] EXCEPTION: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File picker error: $e')),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    debugPrint('[FILE_PICKER] File name  : ${picked.name}');
    debugPrint('[FILE_PICKER] File ext   : ${picked.extension}');
    debugPrint('[FILE_PICKER] Bytes count: ${picked.bytes.length}');

    final bytes = picked.bytes;
    final ext = picked.extension;
    final contentType = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() => _replacingTypes.add(doc.documentType));
    try {
      await ref.read(uploadDocumentUseCaseProvider)(
        vendorId: vendor.id,
        documentType: doc.documentType,
        bytes: bytes,
        contentType: contentType,
        customDocumentName: doc.customDocumentName,
      );
      ref.invalidate(vendorDocumentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document replaced successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replace failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _replacingTypes.remove(doc.documentType));
    }
  }

  void _viewDocument(String url) {
    showDialog(
      context: context,
      builder: (_) => _DocumentViewDialog(url: url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncDocs = ref.watch(vendorDocumentsProvider);
    final asyncTypes = ref.watch(documentTypesProvider);

    final docs = asyncDocs.valueOrNull ?? const [];
    // Fall back to the hardcoded list while the DB fetch is in-flight or fails.
    final types = asyncTypes.valueOrNull ?? DocumentTypeModel.fallbackList;

    final uploadedTypeIds = {for (final d in docs) d.documentType};
    final availableTypes =
        types.where((t) => !uploadedTypeIds.contains(t.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Documents'),
        bottom: asyncDocs.isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (asyncDocs.hasError)
            _ErrorBanner(onRetry: () => ref.refresh(vendorDocumentsProvider)),
          if (availableTypes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showUploadDialog(context, availableTypes),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.6)),
                    foregroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Upload Document'),
                ),
              ),
            ),
          if (docs.isEmpty && !asyncDocs.isLoading && !asyncDocs.hasError)
            const _EmptyState()
          else if (docs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Uploaded Documents (${docs.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
              ),
            ),
            ...docs.map(
              (doc) {
                final docType = types
                    .where((t) => t.id == doc.documentType)
                    .firstOrNull;
                return DocumentTile(
                  document: doc,
                  docType: docType,
                  isReplacing: _replacingTypes.contains(doc.documentType),
                  onReplace: () => _replace(doc),
                  onView: () => _viewDocument(doc.documentUrl),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open_rounded,
              size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'No documents uploaded',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload verification documents to complete your profile.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x20EA4335),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Could not load documents.',
              style: TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _DocumentViewDialog extends StatelessWidget {
  const _DocumentViewDialog({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, err, st) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          size: 64, color: AppColors.textHint),
                      SizedBox(height: 8),
                      Text('Unable to load document'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
