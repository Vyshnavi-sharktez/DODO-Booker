import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/landing_page_section.dart';
import '../../domain/models/section_type.dart';

class PreviewDialog extends StatelessWidget {
  const PreviewDialog({super.key, required this.sections});
  final List<LandingPageSection> sections;

  static Future<void> show(
    BuildContext context,
    List<LandingPageSection> sections,
  ) {
    final enabled = sections.where((s) => s.isEnabled).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return showDialog<void>(
      context: context,
      builder: (_) => PreviewDialog(sections: enabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.preview_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Landing Page Preview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${sections.length} section${sections.length == 1 ? '' : 's'} — enabled, in display order',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),

            // ── Section list ──────────────────────────────────────────────
            Expanded(
              child: sections.isEmpty
                  ? const Center(
                      child: Text(
                        'No enabled sections.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: sections.length,
                      separatorBuilder: (_, __) =>
                          const _SectionConnector(),
                      itemBuilder: (_, i) =>
                          _PreviewCard(section: sections[i], index: i),
                    ),
            ),

            // ── Footer note ───────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This preview shows the draft state. Click Publish to make these sections live for customers.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
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

// ── Individual preview card ───────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.section, required this.index});
  final LandingPageSection section;
  final int index;

  @override
  Widget build(BuildContext context) {
    final type = SectionType.fromDbKey(section.sectionType);
    final isCanonical = type?.isCanonical ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Order badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Type icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isCanonical
                  ? AppColors.accent.withValues(alpha: 0.1)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              type?.icon ?? Icons.widgets_rounded,
              size: 18,
              color: isCanonical
                  ? AppColors.accent
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.sectionName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCanonical
                            ? AppColors.accent.withValues(alpha: 0.08)
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        type?.displayName ?? section.sectionType,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isCanonical
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (section.sectionType == 'footer') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Full width',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_configSummary(section) case final String summary
                    when summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!section.isPublished)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Draft',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _configSummary(LandingPageSection s) {
    final title = s.config['title'] as String?;
    final headline = s.config['headline'] as String?;
    if (headline != null && headline.isNotEmpty) return '"$headline"';
    if (title != null && title.isNotEmpty) return '"$title"';
    return '';
  }
}

// ── Connector arrow between cards ─────────────────────────────────────────────

class _SectionConnector extends StatelessWidget {
  const _SectionConnector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 20,
          color: AppColors.border,
        ),
      ),
    );
  }
}
