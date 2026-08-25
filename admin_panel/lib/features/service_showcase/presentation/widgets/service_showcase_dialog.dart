import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../application/providers/service_showcase_providers.dart';

class ServiceShowcaseDialog extends ConsumerStatefulWidget {
  const ServiceShowcaseDialog({super.key, required this.node});

  final CatalogNode node;

  static Future<void> show(BuildContext context, CatalogNode node) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ServiceShowcaseDialog(node: node),
    );
  }

  @override
  ConsumerState<ServiceShowcaseDialog> createState() =>
      _ServiceShowcaseDialogState();
}

class _ServiceShowcaseDialogState
    extends ConsumerState<ServiceShowcaseDialog> {
  // Draft is null until the server state is first loaded.
  // All add/remove changes go here; nothing is written to DB until Publish.
  List<Map<String, dynamic>>? _draft;
  bool _publishing = false;

  CatalogNode get node => widget.node;

  // Seed draft from server on first load; subsequent server updates are ignored.
  void _initDraft(List<Map<String, dynamic>> serverImages) {
    _draft ??= List.from(serverImages);
  }

  void _draftRemove(String bookingImageId) {
    setState(() {
      _draft!.removeWhere(
          (i) => i['booking_image_id'] == bookingImageId);
    });
  }

  void _draftAdd(List<Map<String, dynamic>> newItems) {
    setState(() {
      final existing =
          _draft!.map((i) => i['booking_image_id'] as String).toSet();
      for (final item in newItems) {
        final id = item['booking_image_id'] as String;
        if (!existing.contains(id)) _draft!.add(item);
      }
    });
  }

  Future<void> _openPicker() async {
    final draftIds =
        (_draft ?? []).map((i) => i['booking_image_id'] as String).toSet();

    final selected = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImagePickerDialog(
        nodeId: node.id,
        alreadyShowcasedIds: draftIds,
      ),
    );

    if (selected == null || selected.isEmpty) return;

    // Build draft entries from available images provider (already loaded).
    final available =
        ref.read(availableBookingImagesProvider(node.id)).valueOrNull ?? [];
    final newItems = selected.map((id) {
      final img = available.firstWhere(
        (a) => a['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      return <String, dynamic>{
        'booking_image_id': id,
        'sort_order': (_draft?.length ?? 0),
        'booking_images': {
          'image_url': img['image_url'],
          'image_type': img['image_type'],
        },
      };
    }).toList();

    _draftAdd(newItems);
  }

  Future<void> _publish(List<Map<String, dynamic>> serverImages) async {
    if (_publishing) return;
    final notifier =
        ref.read(serviceShowcaseNotifierProvider(node.id).notifier);
    final draft = _draft ?? [];

    final serverIds =
        serverImages.map((i) => i['booking_image_id'] as String).toSet();
    final draftIds =
        draft.map((i) => i['booking_image_id'] as String).toSet();

    final toRemove = serverIds.difference(draftIds).toList();
    final toAdd = draftIds.difference(serverIds).toList();

    setState(() => _publishing = true);
    try {
      for (final id in toRemove) {
        await notifier.remove(id);
      }
      if (toAdd.isNotEmpty) await notifier.add(toAdd);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverAsync =
        ref.watch(serviceShowcaseNotifierProvider(node.id));

    return serverAsync.when(
      loading: () => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 620, maxHeight: 600),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error: $e'),
        ),
      ),
      data: (serverImages) {
        _initDraft(serverImages);
        final draft = _draft!;

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 620, maxHeight: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  node: node,
                  onPick: _openPicker,
                ),
                Expanded(
                  child: draft.isEmpty
                      ? _EmptyState(onPick: _openPicker)
                      : _ShowcaseGrid(
                          images: draft,
                          onRemove: _draftRemove,
                        ),
                ),
                _PublishFooter(
                  publishing: _publishing,
                  onPublish: () => _publish(serverImages),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final CatalogNode node;
  final VoidCallback onPick;

  const _Header({required this.node, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.photo_library_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Showcase Photos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  node.name,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
            label: const Text('Pick Images'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Publish footer ────────────────────────────────────────────────────────────

class _PublishFooter extends StatelessWidget {
  final bool publishing;
  final VoidCallback onPublish;

  const _PublishFooter({required this.publishing, required this.onPublish});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: publishing ? null : onPublish,
          icon: publishing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.publish_rounded, size: 18),
          label: Text(publishing ? 'Publishing…' : 'Publish Images'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 52, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('No showcase photos',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Click "Pick Images" to select from vendor-uploaded\nbooking photos.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
            label: const Text('Pick Images'),
          ),
        ],
      ),
    );
  }
}

// ── Showcased image grid ──────────────────────────────────────────────────────

class _ShowcaseGrid extends StatelessWidget {
  final List<Map<String, dynamic>> images;
  final void Function(String bookingImageId) onRemove;

  const _ShowcaseGrid({required this.images, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final before = images.where((i) {
      final img = i['booking_images'] as Map<String, dynamic>?;
      return img?['image_type'] == 'before';
    }).toList();
    final after = images.where((i) {
      final img = i['booking_images'] as Map<String, dynamic>?;
      return img?['image_type'] == 'after';
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (before.isNotEmpty) ...[
            _TypeSection(
              label: 'Before',
              labelColor: const Color(0xFFE53E3E),
              photos: before,
              onRemove: onRemove,
            ),
            if (after.isNotEmpty) const SizedBox(height: 20),
          ],
          if (after.isNotEmpty)
            _TypeSection(
              label: 'After',
              labelColor: const Color(0xFF38A169),
              photos: after,
              onRemove: onRemove,
            ),
        ],
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  final String label;
  final Color labelColor;
  final List<Map<String, dynamic>> photos;
  final void Function(String bookingImageId) onRemove;

  const _TypeSection({
    required this.label,
    required this.labelColor,
    required this.photos,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TypeChip(label: label, color: labelColor),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: photos.map((p) {
            final img = p['booking_images'] as Map<String, dynamic>?;
            final url = img?['image_url'] as String? ?? '';
            final bookingImageId = p['booking_image_id'] as String;
            return _ShowcasePhotoTile(
              url: url,
              onRemove: () => onRemove(bookingImageId),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ShowcasePhotoTile extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _ShowcasePhotoTile({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 100,
              height: 100,
              color: AppColors.background,
              child: const Icon(Icons.broken_image_outlined,
                  color: AppColors.textSecondary),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Image picker dialog ───────────────────────────────────────────────────────

class _ImagePickerDialog extends ConsumerStatefulWidget {
  final String nodeId;
  final Set<String> alreadyShowcasedIds;

  const _ImagePickerDialog({
    required this.nodeId,
    required this.alreadyShowcasedIds,
  });

  @override
  ConsumerState<_ImagePickerDialog> createState() =>
      _ImagePickerDialogState();
}

class _ImagePickerDialogState extends ConsumerState<_ImagePickerDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final availableAsync =
        ref.watch(availableBookingImagesProvider(widget.nodeId));

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_photo_alternate_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Select Images to Showcase',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: availableAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading images: $e')),
                data: (images) {
                  if (images.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No before/after images found for this service.\n'
                          'Vendors upload these when completing bookings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }

                  final before = images
                      .where((i) => i['image_type'] == 'before')
                      .toList();
                  final after = images
                      .where((i) => i['image_type'] == 'after')
                      .toList();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (before.isNotEmpty) ...[
                          _PickerSection(
                            label: 'Before',
                            labelColor: const Color(0xFFE53E3E),
                            images: before,
                            selected: _selected,
                            alreadyShowcased: widget.alreadyShowcasedIds,
                            onToggle: (id, v) => setState(() {
                              if (v) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                          ),
                          if (after.isNotEmpty) const SizedBox(height: 16),
                        ],
                        if (after.isNotEmpty)
                          _PickerSection(
                            label: 'After',
                            labelColor: const Color(0xFF38A169),
                            images: after,
                            selected: _selected,
                            alreadyShowcased: widget.alreadyShowcasedIds,
                            onToggle: (id, v) => setState(() {
                              if (v) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () =>
                            Navigator.of(context).pop(_selected.toList()),
                    child: Text(
                      _selected.isEmpty
                          ? 'Add Selected'
                          : 'Add (${_selected.length})',
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

class _PickerSection extends StatelessWidget {
  final String label;
  final Color labelColor;
  final List<Map<String, dynamic>> images;
  final Set<String> selected;
  final Set<String> alreadyShowcased;
  final void Function(String id, bool selected) onToggle;

  const _PickerSection({
    required this.label,
    required this.labelColor,
    required this.images,
    required this.selected,
    required this.alreadyShowcased,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TypeChip(label: label, color: labelColor),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: images.map((img) {
            final id = img['id'] as String;
            final url = img['image_url'] as String;
            final isAlready = alreadyShowcased.contains(id);
            final isSel = selected.contains(id);
            return _PickerPhotoTile(
              url: url,
              isAlreadyShowcased: isAlready,
              isSelected: isSel,
              onTap: isAlready ? null : () => onToggle(id, !isSel),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PickerPhotoTile extends StatelessWidget {
  final String url;
  final bool isAlreadyShowcased;
  final bool isSelected;
  final VoidCallback? onTap;

  const _PickerPhotoTile({
    required this.url,
    required this.isAlreadyShowcased,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 90,
              height: 90,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 90,
                height: 90,
                color: AppColors.background,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textSecondary),
              ),
            ),
          ),
          // Already-showcased: full overlay with checkmark
          if (isAlreadyShowcased)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
          // Selectable: border + dim + check icon when selected
          if (!isAlreadyShowcased) ...[
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.black.withValues(alpha: 0.35)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            ),
            if (isSelected)
              const Positioned(
                top: 5,
                right: 5,
                child: Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Shared label chip ─────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TypeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
