import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/bookings_provider.dart';

/// Bottom sheet that lets the vendor upload before/after service photos.
///
/// Returns `true` via [Navigator.pop] when the user taps "Done" with ≥ 1
/// uploaded photo, or `null` if they cancel.
class ServicePhotoSheet extends ConsumerStatefulWidget {
  const ServicePhotoSheet({
    super.key,
    required this.bookingId,
    required this.imageType,
  });

  final String bookingId;
  final String imageType; // 'before' | 'after'

  static Future<bool?> show(
    BuildContext context, {
    required String bookingId,
    required String imageType,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ServicePhotoSheet(
        bookingId: bookingId,
        imageType: imageType,
      ),
    );
  }

  @override
  ConsumerState<ServicePhotoSheet> createState() => _ServicePhotoSheetState();
}

class _ServicePhotoSheetState extends ConsumerState<ServicePhotoSheet> {
  final _picker = ImagePicker();
  final List<String> _urls = [];
  bool _isUploading = false;

  String get _title =>
      widget.imageType == 'before' ? 'Before Service Photos' : 'After Service Photos';

  String get _subtitle => widget.imageType == 'before'
      ? 'Capture the work area BEFORE starting the service. At least 1 photo required.'
      : 'Capture the completed work AFTER the service. At least 1 photo required.';

  Future<void> _addPhoto() async {
    if (_isUploading) return;

    ImageSource? source;
    if (kIsWeb) {
      source = ImageSource.gallery;
    } else {
      source = await showDialog<ImageSource>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Add Photo'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              child: const Row(children: [
                Icon(Icons.camera_alt_outlined),
                SizedBox(width: 12),
                Text('Take Photo'),
              ]),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              child: const Row(children: [
                Icon(Icons.photo_library_outlined),
                SizedBox(width: 12),
                Text('Choose from Gallery'),
              ]),
            ),
          ],
        ),
      );
    }
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open image picker: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final contentType = picked.mimeType ?? 'image/jpeg';
      final vendorName = ref.read(currentVendorUserProvider)?.name;
      final url = await ref.read(bookingImagesDatasourceProvider).uploadAndSave(
            bookingId: widget.bookingId,
            imageType: widget.imageType,
            bytes: bytes,
            contentType: contentType,
            uploadedBy: vendorName,
          );
      if (mounted) setState(() => _urls.add(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDone = _urls.isNotEmpty && !_isUploading;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    widget.imageType == 'before'
                        ? Icons.photo_camera_outlined
                        : Icons.camera_enhance_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),

            // Photo grid / empty state
            Flexible(
              child: _urls.isEmpty && !_isUploading
                  ? InkWell(
                      onTap: _addPhoto,
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  size: 52, color: AppColors.textHint),
                              const SizedBox(height: 12),
                              Text(
                                'Tap to add a photo',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ..._urls.map((url) => _PhotoTile(url: url)),
                          if (_isUploading)
                            const _UploadingTile()
                          else
                            _AddPhotoTile(onTap: _addPhoto),
                        ],
                      ),
                    ),
            ),

            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canDone
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        _urls.isEmpty
                            ? 'Done'
                            : 'Done (${_urls.length} photo${_urls.length == 1 ? '' : 's'})',
                      ),
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

// ── Helper widgets ────────────────────────────────────────────────────────────

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 100,
          height: 100,
          color: AppColors.border,
          child: const Icon(Icons.broken_image_outlined,
              color: AppColors.textHint),
        ),
      ),
    );
  }
}

class _UploadingTile extends StatelessWidget {
  const _UploadingTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4), width: 2),
          borderRadius: BorderRadius.circular(8),
          color: AppColors.primaryLight.withValues(alpha: 0.3),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: AppColors.primary, size: 28),
            SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(color: AppColors.primary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
