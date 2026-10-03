import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

/// A form field replacement for image URL text inputs.
///
/// Shows a thumbnail when a URL is set; shows an "Upload image" button when
/// empty. Picks a file via [FilePicker], uploads it to Supabase Storage, and
/// calls [onChanged] with the resulting public URL.
///
/// To remove the image, the user taps "Remove" and [onChanged] is called with
/// null.
///
/// Usage:
/// ```dart
/// ImageUploadField(
///   label: 'Web Image',
///   value: _imageUrl,
///   onChanged: (url) => setState(() => _imageUrl = url),
///   bucket: 'catalog-images',
///   pathPrefix: 'catalog-nodes/',
/// )
/// ```
class ImageUploadField extends StatefulWidget {
  const ImageUploadField({
    super.key,
    required this.label,
    this.value,
    required this.onChanged,
    required this.bucket,
    required this.pathPrefix,
  });

  /// Label shown above the field.
  final String label;

  /// Current image URL, or null / empty string when no image is set.
  final String? value;

  /// Called with the public URL after a successful upload, or null when
  /// the image is removed.
  final ValueChanged<String?> onChanged;

  /// Supabase Storage bucket name (e.g. 'catalog-images').
  final String bucket;

  /// Path prefix inside the bucket (e.g. 'catalog-nodes/'). The file name
  /// is generated as `$pathPrefix<timestamp>.<ext>`.
  final String pathPrefix;

  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  bool _uploading = false;

  static const _mimeMap = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
  };

  Future<void> _pick() async {
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
    final mime = _mimeMap[ext] ?? 'image/jpeg';
    final path =
        '${widget.pathPrefix}${DateTime.now().millisecondsSinceEpoch}.$ext';

    setState(() => _uploading = true);
    try {
      await Supabase.instance.client.storage.from(widget.bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      final url = Supabase.instance.client.storage
          .from(widget.bucket)
          .getPublicUrl(path);
      if (mounted) {
        setState(() => _uploading = false);
        widget.onChanged(url);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Upload failed. Ensure a public bucket "${widget.bucket}" '
            'exists in Supabase Storage.\n$e',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.value?.isNotEmpty == true) ? widget.value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (url != null) ...[
          // ── Has image: thumbnail + Replace + Remove ──────────────────────
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  url,
                  width: 96,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, err, stack) => Container(
                    width: 96,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_uploading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.swap_vert_rounded, size: 14),
                  label: const Text('Replace'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => widget.onChanged(null),
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ] else if (_uploading) ...[
          // ── Uploading: spinner + label ───────────────────────────────────
          const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'Uploading…',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ] else ...[
          // ── No image: Upload button ──────────────────────────────────────
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Upload image'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 13),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      ],
    );
  }
}
