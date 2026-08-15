import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class PromoBannerSection extends StatelessWidget {
  const PromoBannerSection({super.key, required this.config});
  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final title = config['title'] as String? ?? '';
    final subtitle = config['subtitle'] as String?;
    final ctaText = config['cta_text'] as String?;
    final imageUrl = config['image_url'] as String?;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
      height: isDesktop ? 200 : 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.primary,
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withAlpha(120),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.all(isDesktop ? 36 : 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isDesktop ? 22 : 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 13,
                      color: Colors.white.withAlpha(204),
                      height: 1.4,
                    ),
                  ),
                ],
                if (ctaText != null && ctaText.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                      elevation: 0,
                    ),
                    child: Text(ctaText),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
