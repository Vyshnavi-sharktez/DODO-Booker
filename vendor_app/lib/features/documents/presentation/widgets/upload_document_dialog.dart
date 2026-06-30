import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/vendor_document.dart';
import '../utils/document_file_picker.dart'
    if (dart.library.html) '../utils/document_file_picker_web.dart'
    if (dart.library.io) '../utils/document_file_picker_mobile.dart';

class UploadDocumentDialog extends StatefulWidget {
  const UploadDocumentDialog({
    super.key,
    required this.availableTypes,
    required this.onUpload,
  });

  final List<DocumentTypeModel> availableTypes;
  final Future<void> Function(
    String documentType,
    Uint8List bytes,
    String contentType,
    String? customDocumentName,
  ) onUpload;

  @override
  State<UploadDocumentDialog> createState() => _UploadDocumentDialogState();
}

class _UploadDocumentDialogState extends State<UploadDocumentDialog> {
  DocumentTypeModel? _type;
  PickedDocument? _file;
  bool _uploading = false;
  String? _error;

  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isOther => _type?.id == 'other';

  Future<void> _pickFile() async {
    debugPrint(
      '[FILE_PICKER] Select file clicked — platform: ${defaultTargetPlatform.name}, kIsWeb: $kIsWeb',
    );
    try {
      debugPrint('[FILE_PICKER] Opening picker…');
      final picked = await pickDocumentFile();
      debugPrint(
        '[FILE_PICKER] Picker returned: ${picked == null ? "null (cancelled)" : picked.name}',
      );
      if (picked != null && mounted) {
        debugPrint('[FILE_PICKER] File name  : ${picked.name}');
        debugPrint('[FILE_PICKER] File ext   : ${picked.extension}');
        debugPrint('[FILE_PICKER] Bytes count: ${picked.bytes.length}');
        setState(() {
          _file = picked;
          _error = null;
        });
      }
    } catch (e, st) {
      debugPrint('[FILE_PICKER] EXCEPTION: $e');
      debugPrint('[FILE_PICKER] STACK    : $st');
      if (mounted) setState(() => _error = 'File picker error: $e');
    }
  }

  Future<void> _submit() async {
    if (_type == null) {
      setState(() => _error = 'Select a document type.');
      return;
    }
    if (_isOther && _nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for this document.');
      return;
    }
    if (_file == null) {
      setState(() => _error = 'Select a file to upload.');
      return;
    }

    debugPrint('[FILE_PICKER] Upload started — type: ${_type!.id}, file: ${_file!.name}');

    final bytes = _file!.bytes;
    final ext = _file!.extension;
    final contentType = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final customName = _isOther ? _nameController.text.trim() : null;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await widget.onUpload(_type!.id, bytes, contentType, customName);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Document'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownMenu<DocumentTypeModel>(
              label: const Text('Document Type'),
              leadingIcon: const Icon(Icons.description_outlined),
              hintText: 'Select document type',
              expandedInsets: EdgeInsets.zero,
              enableFilter: false,
              enableSearch: false,
              enabled: !_uploading,
              onSelected: (v) => setState(() {
                _type = v;
                _nameController.clear();
                _error = null;
              }),
              dropdownMenuEntries: widget.availableTypes
                  .map((t) => DropdownMenuEntry(value: t, label: t.label))
                  .toList(),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
              child: _isOther
                  ? Padding(
                      key: const ValueKey('name-field'),
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: _nameController,
                        enabled: !_uploading,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Other Document Name',
                          hintText: 'e.g. Trade License, ISO Certificate',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('name-hidden')),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                alignment: Alignment.centerLeft,
              ),
              icon: Icon(
                _file != null
                    ? Icons.insert_drive_file_outlined
                    : Icons.attach_file_rounded,
              ),
              label: Text(
                _file != null ? _file!.name : 'Select file…',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _uploading ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: _uploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Upload'),
        ),
      ],
    );
  }
}
