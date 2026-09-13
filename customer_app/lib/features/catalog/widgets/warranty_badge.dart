import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/app_modal_dialog.dart';

// Design tokens matching catalog_node_screen.dart
const _kInk = Color(0xFF1A1714);
const _kMuted = Color(0xFF6E6A64);
const _kGreen = Color(0xFF16A34A);
const _kGreenBg = Color(0xFFDCFCE7);

// ═══════════════════════════════════════════════════════════════════════════════
// WarrantyBadge — tappable green chip shown below the price on any service that
// has warranty enabled.  Opens WarrantyInfoDialog on tap.
// ═══════════════════════════════════════════════════════════════════════════════

class WarrantyBadge extends StatelessWidget {
  const WarrantyBadge({
    super.key,
    required this.warrantyDays,
    this.warrantyCovers,
    this.warrantyExclusions,
  });

  final int warrantyDays;
  final String? warrantyCovers;
  final String? warrantyExclusions;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => AppModalDialog.show(
          context: context,
          child: WarrantyInfoDialog(
            warrantyDays: warrantyDays,
            warrantyCovers: warrantyCovers,
            warrantyExclusions: warrantyExclusions,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _kGreenBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kGreen.withAlpha(80)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined, size: 14, color: _kGreen),
              const SizedBox(width: 6),
              Text(
                '$warrantyDays Day Warranty',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kGreen,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.info_outline_rounded, size: 12, color: _kGreen),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WarrantyInfoDialog — compact floating modal showing duration + covers + exclusions
// ═══════════════════════════════════════════════════════════════════════════════

class WarrantyInfoDialog extends StatelessWidget {
  const WarrantyInfoDialog({
    super.key,
    required this.warrantyDays,
    this.warrantyCovers,
    this.warrantyExclusions,
  });

  final int warrantyDays;
  final String? warrantyCovers;
  final String? warrantyExclusions;

  @override
  Widget build(BuildContext context) {
    final covers = warrantyCovers?.trim() ?? '';
    final exclusions = warrantyExclusions?.trim() ?? '';

    return AppModalDialog(
      title: 'Warranty Coverage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kGreen.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGreen.withAlpha(50)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: _kGreen),
                const SizedBox(width: 8),
                Text(
                  '$warrantyDays Day Warranty',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
              ],
            ),
          ),
          if (covers.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              "What's Covered",
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _kInk),
            ),
            const SizedBox(height: 8),
            ..._bullets(covers, _kGreen),
          ],
          if (exclusions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              "What's Not Covered",
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _kInk),
            ),
            const SizedBox(height: 8),
            ..._bullets(exclusions, _kMuted),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static List<Widget> _bullets(String text, Color dotColor) {
    return text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: dotColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line.trim(),
                      style: const TextStyle(
                          fontSize: 13, color: _kMuted, height: 1.5),
                    ),
                  ),
                ],
              ),
            ))
        .toList();
  }
}
