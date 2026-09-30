import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../providers/bookings_provider.dart';

typedef _MediaItem = ({String url, String mediaType});

/// Bottom sheet that lets the vendor upload before/after service photos and videos.
///
/// Returns `true` via [Navigator.pop] when the user taps "Done" with ≥ 1
/// uploaded file, or `null` if they cancel.
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
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
  final List<_MediaItem> _media = [];
  bool _isUploading = false;

  String get _title =>
      widget.imageType == 'before' ? 'Before Service Media' : 'After Service Media';

  String get _subtitle => widget.imageType == 'before'
      ? 'Capture the work area BEFORE starting. At least 1 photo or video required.'
      : 'Capture the completed work AFTER service. At least 1 photo or video required.';

  static String _mediaTypeFrom(String? mimeType) {
    if (mimeType != null && mimeType.startsWith('video/')) return 'video';
    return 'photo';
  }

  Future<void> _addMedia() async {
    if (_isUploading) return;

    if (kIsWeb) {
      await _pickAndUpload(await _picker.pickMultipleMedia());
      return;
    }

    final choice = await showDialog<_PickChoice>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Add Media'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_PickChoice.cameraPhoto),
            child: const Row(children: [
              Icon(Icons.camera_alt_outlined),
              SizedBox(width: 12),
              Text('Take Photo'),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_PickChoice.cameraVideo),
            child: const Row(children: [
              Icon(Icons.videocam_outlined),
              SizedBox(width: 12),
              Text('Record Video'),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_PickChoice.gallery),
            child: const Row(children: [
              Icon(Icons.photo_library_outlined),
              SizedBox(width: 12),
              Text('Choose from Gallery'),
            ]),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    List<XFile> picked = [];
    try {
      switch (choice) {
        case _PickChoice.cameraPhoto:
          final f = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 80,
            maxWidth: 1920,
          );
          if (f != null) picked.add(f);
        case _PickChoice.cameraVideo:
          final f = await _picker.pickVideo(source: ImageSource.camera);
          if (f != null) picked.add(f);
        case _PickChoice.gallery:
          picked = await _picker.pickMultipleMedia();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open picker: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (picked.isEmpty || !mounted) return;
    await _pickAndUpload(picked);
  }

  Future<void> _pickAndUpload(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final vendorName = ref.read(currentVendorUserProvider)?.name;
      for (final file in files) {
        final mediaType = _mediaTypeFrom(file.mimeType);
        final contentType = file.mimeType ??
            (mediaType == 'video' ? 'video/mp4' : 'image/jpeg');
        final bytes = await file.readAsBytes();
        final url = await ref.read(bookingImagesDatasourceProvider).uploadAndSave(
              bookingId: widget.bookingId,
              imageType: widget.imageType,
              bytes: bytes,
              contentType: contentType,
              uploadedBy: vendorName,
              mediaType: mediaType,
            );
        if (mounted) setState(() => _media.add((url: url, mediaType: mediaType)));
      }
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
    final canDone = _media.isNotEmpty && !_isUploading;
    final count = _media.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
              const Divider(height: 1),

              // Media grid / empty state
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _media.isEmpty && !_isUploading
                    ? InkWell(
                        onTap: _addMedia,
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 52, color: AppColors.textHint),
                                const SizedBox(height: 12),
                                Text(
                                  'Tap to add photos or videos',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
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
                            ..._media.map((m) => m.mediaType == 'video'
                                ? _VideoTile(url: m.url)
                                : _PhotoTile(url: m.url)),
                            if (_isUploading)
                              const _UploadingTile()
                            else
                              _AddMediaTile(onTap: _addMedia),
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
                          minimumSize: const Size(double.infinity, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                          minimumSize: const Size(double.infinity, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          count == 0
                              ? 'Done'
                              : 'Done ($count file${count == 1 ? '' : 's'})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PickChoice { cameraPhoto, cameraVideo, gallery }

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

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_rounded, color: AppColors.primary, size: 34),
          SizedBox(height: 4),
          Text(
            'Video',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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

class _AddMediaTile extends StatelessWidget {
  const _AddMediaTile({required this.onTap});
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
