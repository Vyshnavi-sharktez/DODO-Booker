import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class WhyDodoSection extends StatelessWidget {
  const WhyDodoSection({super.key});

  static const _items = [
    _TrustItem(
      icon: Icons.verified_user_rounded,
      title: 'Verified Professionals',
      description:
          'Every service provider is background-checked and certified before joining our platform.',
    ),
    _TrustItem(
      icon: Icons.receipt_long_rounded,
      title: 'Transparent Pricing',
      description:
          'No hidden charges — what you see is what you pay. Get instant quotes upfront.',
    ),
    _TrustItem(
      icon: Icons.lock_rounded,
      title: 'Secure Booking',
      description:
          'Your payments and personal data are protected with bank-grade encryption.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
      padding: EdgeInsets.all(isDesktop ? 32 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFDF5), Color(0xFFFFF8E6)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withAlpha(60), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why Choose DODO Booker?',
            style: TextStyle(
              fontSize: isDesktop ? 20 : 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Everything you need for a seamless home services experience.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: isDesktop ? 28 : 20),
          isDesktop
              ? Row(
                  children: [
                    for (int i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 20),
                      Expanded(child: _TrustCard(item: _items[i])),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (int i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _TrustCard(item: _items[i]),
                    ],
                  ],
                ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _TrustItem {
  final IconData icon;
  final String title;
  final String description;
  const _TrustItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

// ── Individual card ───────────────────────────────────────────────────────────

class _TrustCard extends StatelessWidget {
  final _TrustItem item;
  const _TrustCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.goldLight,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(item.icon, size: 22, color: AppColors.gold),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
