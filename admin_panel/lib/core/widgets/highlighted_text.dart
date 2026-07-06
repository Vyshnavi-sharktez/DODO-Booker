import 'package:flutter/material.dart';

/// Renders [text] with every occurrence of [query] highlighted in yellow.
///
/// Falls back to a plain [Text] widget when [query] is empty or there is no
/// match — zero overhead in the common non-search case.
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final TextOverflow overflow;
  final int? maxLines;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines,
  });

  static const _kHighlightBg = Color(0xFFFFF176);
  static const _kHighlightFg = Color(0xFF1A202C);

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty || text.isEmpty) {
      return Text(text, style: style, overflow: overflow, maxLines: maxLines);
    }

    final lText = text.toLowerCase();
    final lQuery = q.toLowerCase();

    if (!lText.contains(lQuery)) {
      return Text(text, style: style, overflow: overflow, maxLines: maxLines);
    }

    final baseStyle = style ?? const TextStyle();
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: _kHighlightBg,
      color: _kHighlightFg,
      fontWeight: FontWeight.w700,
    );

    final spans = <TextSpan>[];
    int cursor = 0;
    while (cursor < text.length) {
      final idx = lText.indexOf(lQuery, cursor);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
        break;
      }
      if (idx > cursor) {
        spans.add(
            TextSpan(text: text.substring(cursor, idx), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: highlightStyle,
      ));
      cursor = idx + q.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}
