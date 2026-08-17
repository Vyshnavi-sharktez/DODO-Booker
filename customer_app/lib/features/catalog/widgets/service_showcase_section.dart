import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/catalog_providers.dart';

/// Displays Admin-curated before/after showcase images for a service.
/// Renders nothing when no images have been selected by Admin.
class ServiceShowcaseSection extends ConsumerWidget {
  final String serviceId;

  const ServiceShowcaseSection({super.key, required this.serviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(serviceShowcaseImagesProvider(serviceId));

    return imagesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (images) {
        if (images.isEmpty) return const SizedBox.shrink();

        final before =
            images.where((i) => i['image_type'] == 'before').toList();
        final after =
            images.where((i) => i['image_type'] == 'after').toList();
        if (before.isEmpty && after.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PHOTOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: 12),
              if (before.isNotEmpty) ...[
                _PhotoRow(label: 'Before', photos: before),
                if (after.isNotEmpty) const SizedBox(height: 14),
              ],
              if (after.isNotEmpty)
                _PhotoRow(label: 'After', photos: after),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> photos;

  const _PhotoRow({required this.label, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = photos[i]['image_url'] as String;
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 90,
                      height: 90,
                      color: AppColors.background,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => Container(
                    width: 90,
                    height: 90,
                    color: AppColors.background,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
