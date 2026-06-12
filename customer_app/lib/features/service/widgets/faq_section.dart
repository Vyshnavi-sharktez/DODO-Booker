import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/faq_model.dart';

class FaqSection extends StatelessWidget {
  final List<FaqModel> faqs;

  const FaqSection({super.key, required this.faqs});

  @override
  Widget build(BuildContext context) {
    if (faqs.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Frequently Asked Questions',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...faqs.map((faq) => _FaqTile(faq: faq)),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final FaqModel faq;

  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textSecondary,
        title: Text(
          faq.question,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        children: [
          Text(
            faq.answer,
            style: tt.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
