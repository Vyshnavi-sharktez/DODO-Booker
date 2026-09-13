import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';

const kVendorContentBucket = 'vendor-requests';

// ── Section header ──────────────────────────────────────────────────────────

class ServiceSectionHeader extends StatelessWidget {
  const ServiceSectionHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

// ── Editable text list ──────────────────────────────────────────────────────

class ServiceEditableItemList extends StatefulWidget {
  const ServiceEditableItemList({
    super.key,
    required this.items,
    required this.onChanged,
    required this.addLabel,
  });
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;

  @override
  State<ServiceEditableItemList> createState() =>
      _ServiceEditableItemListState();
}

class _ServiceEditableItemListState extends State<ServiceEditableItemList> {
  late List<String> _items;
  bool _adding = false;
  final _addCtrl = TextEditingController();
  int? _editingIndex;
  final _editCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  @override
  void didUpdateWidget(ServiceEditableItemList old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items) _items = List.from(widget.items);
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _addCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _items.add(text);
        _addCtrl.clear();
        _adding = false;
      });
      widget.onChanged(List.from(_items));
    } else {
      setState(() => _adding = false);
    }
  }

  void _startEdit(int i) {
    setState(() {
      _editingIndex = i;
      _editCtrl.text = _items[i];
    });
  }

  void _commitEdit(int i) {
    final text = _editCtrl.text.trim();
    if (text.isNotEmpty && text != _items[i]) {
      setState(() => _items[i] = text);
      widget.onChanged(List.from(_items));
    }
    setState(() => _editingIndex = null);
  }

  void _delete(int i) {
    setState(() => _items.removeAt(i));
    widget.onChanged(List.from(_items));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_items.isEmpty && !_adding)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No items yet.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        if (_items.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorder: (oldIdx, newIdx) {
              if (newIdx > oldIdx) newIdx--;
              setState(() {
                final item = _items.removeAt(oldIdx);
                _items.insert(newIdx, item);
                if (_editingIndex == oldIdx) _editingIndex = newIdx;
              });
              widget.onChanged(List.from(_items));
            },
            proxyDecorator: (child, _, _) => Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                child: child),
            itemBuilder: (_, i) {
              final isEditing = _editingIndex == i;
              return Container(
                key: ValueKey('item_$i'),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.drag_handle_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: isEditing
                          ? TextField(
                              controller: _editCtrl,
                              autofocus: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 6)),
                              onSubmitted: (_) => _commitEdit(i),
                            )
                          : GestureDetector(
                              onDoubleTap: () => _startEdit(i),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Text(_items[i],
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                    ),
                    if (isEditing)
                      IconButton(
                        icon: const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.success),
                        onPressed: () => _commitEdit(i),
                        tooltip: 'Save',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 14, color: AppColors.textSecondary),
                        onPressed: () => _startEdit(i),
                        tooltip: 'Edit',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 14, color: AppColors.error),
                      onPressed: () => _delete(i),
                      tooltip: 'Remove',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            },
          ),
        if (_adding)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.accent),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Enter item…',
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                TextButton(
                  onPressed: _commit,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text('Add', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _adding = false;
                    _addCtrl.clear();
                  }),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _adding = true),
          icon: const Icon(Icons.add_rounded, size: 14),
          label: Text(widget.addLabel, style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
        ),
      ],
    );
  }
}

// ── Before & After image pair editor ────────────────────────────────────────

class ServiceBeforeAfterEditor extends StatefulWidget {
  const ServiceBeforeAfterEditor({
    super.key,
    required this.pairs,
    required this.serviceId,
    required this.onChanged,
  });
  final List<Map<String, String>> pairs;
  final String serviceId;
  final ValueChanged<List<Map<String, String>>> onChanged;

  @override
  State<ServiceBeforeAfterEditor> createState() =>
      _ServiceBeforeAfterEditorState();
}

class _ServiceBeforeAfterEditorState extends State<ServiceBeforeAfterEditor> {
  late List<Map<String, String>> _pairs;

  @override
  void initState() {
    super.initState();
    _pairs = widget.pairs.map((p) => Map<String, String>.from(p)).toList();
  }

  @override
  void didUpdateWidget(ServiceBeforeAfterEditor old) {
    super.didUpdateWidget(old);
    if (old.pairs != widget.pairs) {
      _pairs =
          widget.pairs.map((p) => Map<String, String>.from(p)).toList();
    }
  }

  void _addPair() {
    setState(() => _pairs.add({'before_url': '', 'after_url': ''}));
    widget.onChanged(List.from(_pairs));
  }

  void _deletePair(int i) {
    setState(() => _pairs.removeAt(i));
    widget.onChanged(List.from(_pairs));
  }

  void _setUrl(int i, String key, String url) {
    setState(() => _pairs[i] = Map.from(_pairs[i])..[key] = url);
    widget.onChanged(List.from(_pairs));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pairs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No pairs yet.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _pairs.length,
          onReorder: (oldIdx, newIdx) {
            if (newIdx > oldIdx) newIdx--;
            setState(() {
              final pair = _pairs.removeAt(oldIdx);
              _pairs.insert(newIdx, pair);
            });
            widget.onChanged(List.from(_pairs));
          },
          proxyDecorator: (child, _, _) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: child),
          itemBuilder: (_, i) {
            final pair = _pairs[i];
            return Container(
              key: ValueKey('pair_$i'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pair ${i + 1}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.error),
                        onPressed: () => _deletePair(i),
                        tooltip: 'Remove pair',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ServiceImageUploadField(
                          label: 'Before',
                          url: pair['before_url'] ?? '',
                          serviceId: widget.serviceId,
                          onChanged: (url) => _setUrl(i, 'before_url', url),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ServiceImageUploadField(
                          label: 'After',
                          url: pair['after_url'] ?? '',
                          serviceId: widget.serviceId,
                          onChanged: (url) => _setUrl(i, 'after_url', url),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        TextButton.icon(
          onPressed: _addPair,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 14),
          label: const Text('Add Before/After Pair',
              style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
        ),
      ],
    );
  }
}

// ── Image upload field ───────────────────────────────────────────────────────

class ServiceImageUploadField extends StatefulWidget {
  const ServiceImageUploadField({
    super.key,
    required this.label,
    required this.url,
    required this.serviceId,
    required this.onChanged,
  });
  final String label;
  final String url;
  final String serviceId;
  final ValueChanged<String> onChanged;

  @override
  State<ServiceImageUploadField> createState() =>
      _ServiceImageUploadFieldState();
}

class _ServiceImageUploadFieldState extends State<ServiceImageUploadField> {
  bool _uploading = false;

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
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path =
        '${widget.serviceId}/content/$ts.${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    setState(() => _uploading = true);
    try {
      final mime = const {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
          }[ext] ??
          'image/jpeg';
      await Supabase.instance.client.storage
          .from(kVendorContentBucket)
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: mime, upsert: true));
      final url = Supabase.instance.client.storage
          .from(kVendorContentBucket)
          .getPublicUrl(path);
      if (mounted) {
        setState(() => _uploading = false);
        widget.onChanged(url);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (hasImage)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  widget.url,
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.textSecondary),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => widget.onChanged(''),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _uploading ? null : _pick,
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.edit_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: _uploading ? null : _pick,
            child: Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: _uploading
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent)))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_rounded,
                            size: 20, color: AppColors.textSecondary),
                        SizedBox(height: 4),
                        Text('Upload',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
