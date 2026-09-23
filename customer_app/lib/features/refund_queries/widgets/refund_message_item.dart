import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../models/refund_message_model.dart';

class RefundMessageItem extends StatelessWidget {
  const RefundMessageItem({super.key, required this.message});

  final RefundMessageModel message;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isCustomer = message.isFromCustomer;

    return Align(
      alignment:
          isCustomer ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment:
              isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                isCustomer ? 'You' : 'DODO Support',
                style: tt.labelSmall?.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 3),
            // Bubble
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isCustomer ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isCustomer
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isCustomer
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: isCustomer
                    ? null
                    : Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message text with URL detection
                  if (message.message.isNotEmpty)
                    _MessageText(text: message.message, isCustomer: isCustomer),
                  // Inline image attachments
                  if (message.allAttachmentPaths.isNotEmpty) ...[
                    if (message.message.isNotEmpty) const SizedBox(height: 8),
                    _AttachmentGrid(
                      paths: message.allAttachmentPaths,
                      isCustomer: isCustomer,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                DateFormat('d MMM, h:mm a')
                    .format(message.createdAt.toLocal()),
                style: tt.labelSmall?.copyWith(
                  color: AppColors.textHint,
                  fontSize: 10,
                ),
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
  final bool isCustomer;

  const _MessageText({required this.text, required this.isCustomer});

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
    final tt = Theme.of(context).textTheme;
    final baseColor =
        isCustomer ? Colors.white : AppColors.textPrimary;
    final linkColor =
        isCustomer ? Colors.white : AppColors.primary;

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
        style: tt.bodyMedium?.copyWith(
              color: baseColor,
              height: 1.5,
            ) ??
            TextStyle(fontSize: 13, color: baseColor, height: 1.5),
        children: spans,
      ),
    );
  }
}

// ── Inline image grid ──────────────────────────────────────────────────────────

class _AttachmentGrid extends StatelessWidget {
  final List<String> paths;
  final bool isCustomer;

  const _AttachmentGrid({required this.paths, required this.isCustomer});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: paths
          .map((p) => _SignedImage(path: p, isCustomer: isCustomer))
          .toList(),
    );
  }
}

// ── Single signed image ────────────────────────────────────────────────────────

class _SignedImage extends StatefulWidget {
  final String path;
  final bool isCustomer;

  const _SignedImage({required this.path, required this.isCustomer});

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
    try {
      final url = await Supabase.instance.client.storage
          .from('refund-message-attachments')
          .createSignedUrl(widget.path, 3600);
      if (!mounted) return;
      setState(() {
        _signedUrl = url;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 110.0;

    if (_loading) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: widget.isCustomer
              ? AppColors.primary.withAlpha(80)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.isCustomer
                  ? Colors.white70
                  : AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (_error || _signedUrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: widget.isCustomer
              ? AppColors.primary.withAlpha(60)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined,
                color: widget.isCustomer
                    ? Colors.white70
                    : AppColors.textHint,
                size: 22),
            const SizedBox(height: 4),
            Text(
              'Failed to load',
              style: TextStyle(
                  fontSize: 9,
                  color: widget.isCustomer
                      ? Colors.white70
                      : AppColors.textHint),
            ),
          ],
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
            color: AppColors.surfaceVariant,
            child: const Icon(Icons.broken_image_outlined,
                color: AppColors.textHint),
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
        insetPadding: const EdgeInsets.all(12),
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
