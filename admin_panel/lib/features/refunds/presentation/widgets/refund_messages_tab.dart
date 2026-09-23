import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/refund_providers.dart';
import '../../data/refund_repository.dart';
import '../../domain/models/refund_message.dart';

class RefundMessagesTab extends ConsumerStatefulWidget {
  final String requestId;

  const RefundMessagesTab({super.key, required this.requestId});

  @override
  ConsumerState<RefundMessagesTab> createState() => _RefundMessagesTabState();
}

class _RefundMessagesTabState extends ConsumerState<RefundMessagesTab> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  String? _sendError;

  // Pending attachments: list of (bytes, filename, mimeType)
  final List<_PendingFile> _pendingFiles = [];

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImages() async {
    if (_pendingFiles.length >= 4) {
      setState(() => _sendError = 'Maximum 4 images per message.');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final toAdd = result.files
        .where((f) => f.bytes != null)
        .take(4 - _pendingFiles.length)
        .map((f) {
      final ext = (f.extension ?? 'jpg').toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      return _PendingFile(bytes: f.bytes!, filename: f.name, mimeType: mime);
    });

    setState(() {
      _pendingFiles.addAll(toAdd);
      _sendError = null;
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && _pendingFiles.isEmpty) return;
    if (_sending) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      final repo = ref.read(refundRepositoryProvider);
      final paths = <String>[];

      // Upload attachments first.
      for (final file in _pendingFiles) {
        final path = await repo.uploadMessageAttachment(
          refundRequestId: widget.requestId,
          bytes: file.bytes,
          filename: file.filename,
          mimeType: file.mimeType,
        );
        paths.add(path);
      }

      final messageText = text.isEmpty ? '📎 Image attachment' : text;
      await repo.sendAdminMessage(
        requestId: widget.requestId,
        message: messageText,
        attachmentPaths: paths,
      );

      _msgCtrl.clear();
      _pendingFiles.clear();
      ref.invalidate(refundAdminMessagesProvider(widget.requestId));
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _sendError = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync =
        ref.watch(refundAdminMessagesProvider(widget.requestId));

    return Column(
      children: [
        Expanded(
          child: messagesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Could not load messages: $e',
                  style: const TextStyle(color: Color(0xFFE53E3E))),
            ),
            data: (messages) {
              if (messages.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 36, color: Color(0xFFCBD5E0)),
                      SizedBox(height: 12),
                      Text('No messages yet.',
                          style: TextStyle(color: Color(0xFF718096))),
                    ],
                  ),
                );
              }
              _scrollToBottom();
              return ListView.separated(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _AdminMessageBubble(
                  message: messages[i],
                  repo: ref.read(refundRepositoryProvider),
                ),
              );
            },
          ),
        ),

        // ── Error banner ─────────────────────────────────────────────────────
        if (_sendError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFFF5F5),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 14, color: Color(0xFFE53E3E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_sendError!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFE53E3E))),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => setState(() => _sendError = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        // ── Pending image previews ────────────────────────────────────────────
        if (_pendingFiles.isNotEmpty)
          Container(
            height: 80,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7FAFC),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pendingFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final f = _pendingFiles[i];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        f.bytes,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() => _pendingFiles.removeAt(i)),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53E3E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // ── Input bar ────────────────────────────────────────────────────────
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              // Attach image button
              Tooltip(
                message: 'Attach image (JPG, PNG, WEBP)',
                child: IconButton(
                  icon: const Icon(Icons.attach_file_rounded,
                      color: Color(0xFF718096)),
                  onPressed: _sending ? null : _pickImages,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Type a reply…',
                    hintStyle: const TextStyle(
                        color: Color(0xFFA0AEC0), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF7FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _sending
                      ? AppColors.primary.withAlpha(160)
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _sending ? null : _sendMessage,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded,
                          size: 16, color: Colors.white),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _AdminMessageBubble extends StatelessWidget {
  final RefundMessage message;
  final RefundRepository repo;

  const _AdminMessageBubble({required this.message, required this.repo});

  @override
  Widget build(BuildContext context) {
    final isAdmin = message.isFromAdmin;

    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment:
              isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAdmin ? 'You (Admin)' : 'Customer',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF718096)),
                  ),
                  if (message.isInternal) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6E05E).withAlpha(80),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFD69E2E).withAlpha(80)),
                      ),
                      child: const Text('Internal',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF975A16))),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 3),
            // Bubble
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isAdmin
                    ? AppColors.primary
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isAdmin
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isAdmin
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: isAdmin
                    ? null
                    : Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message text with URL detection
                  _MessageText(
                    text: message.message,
                    isAdmin: isAdmin,
                  ),
                  // Inline images
                  if (message.allAttachmentPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _AttachmentGrid(
                      paths: message.allAttachmentPaths,
                      repo: repo,
                      isAdmin: isAdmin,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                message.formattedTime,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFFA0AEC0)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── URL-aware message text ─────────────────────────────────────────────────────

class _MessageText extends StatelessWidget {
  final String text;
  final bool isAdmin;

  const _MessageText({required this.text, required this.isAdmin});

  static final _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static bool _isSafeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        isAdmin ? Colors.white : const Color(0xFF2D3748);
    final linkColor =
        isAdmin ? Colors.white : AppColors.primary;

    final spans = <InlineSpan>[];
    int last = 0;

    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final url = match.group(0)!;
      if (_isSafeUrl(url)) {
        spans.add(WidgetSpan(
          child: GestureDetector(
            onTap: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(
              url,
              style: TextStyle(
                color: linkColor,
                decoration: TextDecoration.underline,
                decorationColor: linkColor.withAlpha(180),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(text: url));
      }
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 13, color: baseColor, height: 1.5),
        children: spans,
      ),
    );
  }
}

// ── Inline image grid ──────────────────────────────────────────────────────────

class _AttachmentGrid extends StatelessWidget {
  final List<String> paths;
  final RefundRepository repo;
  final bool isAdmin;

  const _AttachmentGrid({
    required this.paths,
    required this.repo,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: paths
          .map((p) => _SignedImage(path: p, repo: repo))
          .toList(),
    );
  }
}

// ── Single signed image ────────────────────────────────────────────────────────

class _SignedImage extends StatefulWidget {
  final String path;
  final RefundRepository repo;

  const _SignedImage({required this.path, required this.repo});

  @override
  State<_SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<_SignedImage> {
  String? _signedUrl;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await widget.repo.getSignedAttachmentUrl(widget.path);
    if (!mounted) return;
    setState(() {
      _signedUrl = url;
      _loading = false;
      _error = url == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const size = 120.0;

    if (_loading) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFEDF2F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_error || _signedUrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFEB2B2)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  color: Color(0xFFFC8181), size: 24),
              SizedBox(height: 4),
              Text('Failed to load',
                  style: TextStyle(
                      fontSize: 9, color: Color(0xFFFC8181))),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _signedUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: const Color(0xFFEDF2F7),
            child: const Icon(Icons.broken_image_outlined,
                color: Color(0xFFA0AEC0)),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    if (_signedUrl == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            child: Image.network(_signedUrl!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _PendingFile {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  const _PendingFile(
      {required this.bytes,
      required this.filename,
      required this.mimeType});
}
