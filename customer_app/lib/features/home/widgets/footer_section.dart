import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../routes/app_router.dart';
import '../../info/screens/contact_screen.dart';
import '../../profile/screens/about_screen.dart';
import '../../profile/screens/privacy_policy_screen.dart';

/// Site-wide footer with brand, navigation links, download buttons, and social icons.
class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  static const _websiteUrl = ContactScreen.websiteUrl;
  static const _supportEmail = ContactScreen.supportEmail;
  static const _supportPhone = ContactScreen.supportPhone;

  static const _googlePlayUrl =
      'https://play.google.com/store/apps/details?id=com.example.customer_app';
  static const _appStoreUrl =
      'https://apps.apple.com/app/dodo-booker/id000000000';

  static const _socialLinks = [
    _SocialLink('Facebook', Icons.public_rounded, 'https://facebook.com/dodobooker'),
    _SocialLink('Instagram', Icons.camera_alt_outlined, 'https://instagram.com/dodobooker'),
    _SocialLink('X (Twitter)', Icons.alternate_email_rounded, 'https://twitter.com/dodobooker'),
    _SocialLink('LinkedIn', Icons.work_outline_rounded, 'https://linkedin.com/company/dodobooker'),
    _SocialLink('YouTube', Icons.play_circle_outline_rounded, 'https://youtube.com/@dodobooker'),
  ];

  static Future<void> openExternalUrl(
    BuildContext context,
    String url, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: mode)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  static Future<void> openEmail(BuildContext context, String email) {
    return openExternalUrl(
      context,
      'mailto:$email',
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<void> openPhone(BuildContext context, String phone) {
    return openExternalUrl(
      context,
      'tel:${phone.replaceAll(' ', '')}',
      mode: LaunchMode.externalApplication,
    );
  }

  static void openInternalPage(
    BuildContext context, {
    required String title,
    required Widget modal,
    required Widget screen,
  }) {
    if (MediaQuery.sizeOf(context).width >= 768) {
      PageSheet.show(context, title: title, child: modal);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }
  }

  static void openRoute(BuildContext context, String route) {
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final isTablet = width >= 768;

    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16,
              vertical: isDesktop ? 48 : 32,
            ),
            child: isDesktop
                ? _DesktopLayout(onLink: (action) => action(context))
                : isTablet
                    ? _TabletLayout(onLink: (action) => action(context))
                    : _MobileLayout(onLink: (action) => action(context)),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16,
              vertical: isDesktop ? 48 : 32,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Text(
              '© ${DateTime.now().year} DODO Booker. All rights reserved.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _FooterAction = void Function(BuildContext context);

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.onLink});

  final void Function(_FooterAction action) onLink;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _BrandColumn(onLink: onLink)),
        const SizedBox(width: 32),
        Expanded(
          flex: 2,
          child: _LinkColumn(
            title: 'About Us',
            links: [
              _FooterLinkData('About DODO Booker', (context) => FooterSection.openInternalPage(
                    context,
                    title: 'About DODO Booker',
                    modal: const AboutScreen(inModal: true),
                    screen: const AboutScreen(),
                  )),
            ],
            onLink: onLink,
          ),
        ),
        Expanded(
          flex: 2,
          child: _LinkColumn(
            title: 'Help & Legal',
            links: [
              _FooterLinkData('Help & Support', (context) => FooterSection.openRoute(context, AppRoutes.help)),
              _FooterLinkData('Privacy Policy', (context) => FooterSection.openInternalPage(
                    context,
                    title: 'Privacy Policy',
                    modal: const PrivacyPolicyScreen(inModal: true),
                    screen: const PrivacyPolicyScreen(),
                  )),
              _FooterLinkData('Terms & Conditions', (context) => FooterSection.openInternalPage(
                    context,
                    title: 'Terms & Conditions',
                    modal: const TermsScreen(inModal: true),
                    screen: const TermsScreen(),
                  )),
              _FooterLinkData('Refund Policy', (context) => FooterSection.openRoute(context, AppRoutes.refundPolicy)),
            ],
            onLink: onLink,
          ),
        ),
        Expanded(
          flex: 2,
          child: _LinkColumn(
            title: 'Contact Us',
            links: [
              _FooterLinkData('Contact Page', (context) => FooterSection.openRoute(context, AppRoutes.contact)),
              _FooterLinkData(FooterSection._supportEmail, (context) => FooterSection.openEmail(context, FooterSection._supportEmail)),
              _FooterLinkData(FooterSection._supportPhone, (context) => FooterSection.openPhone(context, FooterSection._supportPhone)),
              _FooterLinkData('Visit Website', (context) => FooterSection.openExternalUrl(context, FooterSection._websiteUrl)),
            ],
            onLink: onLink,
          ),
        ),
      ],
    );
  }
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({required this.onLink});

  final void Function(_FooterAction action) onLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BrandColumn(onLink: onLink, centered: true),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LinkColumn(
                title: 'About Us',
                links: [
                  _FooterLinkData('About DODO Booker', (context) => FooterSection.openInternalPage(
                        context,
                        title: 'About DODO Booker',
                        modal: const AboutScreen(inModal: true),
                        screen: const AboutScreen(),
                      )),
                ],
                onLink: onLink,
              ),
            ),
            Expanded(
              child: _LinkColumn(
                title: 'Help & Legal',
                links: _helpLegalLinks,
                onLink: onLink,
              ),
            ),
            Expanded(
              child: _LinkColumn(
                title: 'Contact Us',
                links: _contactLinks,
                onLink: onLink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.onLink});

  final void Function(_FooterAction action) onLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BrandColumn(onLink: onLink, centered: true),
        const SizedBox(height: 28),
        _LinkColumn(
          title: 'About Us',
          links: [
            _FooterLinkData('About DODO Booker', (context) => FooterSection.openInternalPage(
                  context,
                  title: 'About DODO Booker',
                  modal: const AboutScreen(inModal: true),
                  screen: const AboutScreen(),
                )),
          ],
          onLink: onLink,
        ),
        const SizedBox(height: 20),
        _LinkColumn(
          title: 'Help & Legal',
          links: _helpLegalLinks,
          onLink: onLink,
        ),
        const SizedBox(height: 20),
        _LinkColumn(
          title: 'Contact Us',
          links: _contactLinks,
          onLink: onLink,
        ),
      ],
    );
  }
}

const _helpLegalLinks = [
  _FooterLinkData('Help & Support', _openHelp),
  _FooterLinkData('Privacy Policy', _openPrivacy),
  _FooterLinkData('Terms & Conditions', _openTerms),
  _FooterLinkData('Refund Policy', _openRefund),
];

const _contactLinks = [
  _FooterLinkData('Contact Page', _openContact),
  _FooterLinkData(FooterSection._supportEmail, _openSupportEmail),
  _FooterLinkData(FooterSection._supportPhone, _openSupportPhone),
  _FooterLinkData('Visit Website', _openWebsite),
];

void _openHelp(BuildContext context) =>
    FooterSection.openRoute(context, AppRoutes.help);

void _openPrivacy(BuildContext context) => FooterSection.openInternalPage(
      context,
      title: 'Privacy Policy',
      modal: const PrivacyPolicyScreen(inModal: true),
      screen: const PrivacyPolicyScreen(),
    );

void _openTerms(BuildContext context) => FooterSection.openInternalPage(
      context,
      title: 'Terms & Conditions',
      modal: const TermsScreen(inModal: true),
      screen: const TermsScreen(),
    );

void _openRefund(BuildContext context) =>
    FooterSection.openRoute(context, AppRoutes.refundPolicy);

void _openContact(BuildContext context) =>
    FooterSection.openRoute(context, AppRoutes.contact);

void _openSupportEmail(BuildContext context) =>
    FooterSection.openEmail(context, FooterSection._supportEmail);

void _openSupportPhone(BuildContext context) =>
    FooterSection.openPhone(context, FooterSection._supportPhone);

void _openWebsite(BuildContext context) =>
    FooterSection.openExternalUrl(context, FooterSection._websiteUrl);

class _BrandColumn extends StatelessWidget {
  const _BrandColumn({
    required this.onLink,
    this.centered = false,
  });

  final void Function(_FooterAction action) onLink;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 56,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.home_repair_service_rounded,
            size: 48,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'DODO Booker',
          textAlign: textAlign,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: centered ? 320 : 280,
          child: Text(
            'Premium home services, delivered by verified professionals you can trust.',
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 12,
          runSpacing: 12,
          children: [
            _DownloadButton(
              label: 'Google Play',
              icon: Icons.android_rounded,
              onTap: () => onLink(
                (ctx) => FooterSection.openExternalUrl(ctx, FooterSection._googlePlayUrl),
              ),
            ),
            _DownloadButton(
              label: 'App Store',
              icon: Icons.phone_iphone_rounded,
              onTap: () => onLink(
                (ctx) => FooterSection.openExternalUrl(ctx, FooterSection._appStoreUrl),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SocialRow(onLink: onLink, centered: centered),
      ],
    );
  }
}

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({
    required this.title,
    required this.links,
    required this.onLink,
  });

  final String title;
  final List<_FooterLinkData> links;
  final void Function(_FooterAction action) onLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 14),
        for (final link in links) ...[
          _FooterLink(
            label: link.label,
            onTap: () => onLink(link.action),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            color: _hovered ? AppColors.primary : AppColors.textSecondary,
            fontWeight: _hovered ? FontWeight.w600 : FontWeight.w400,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(180)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  const _SocialRow({required this.onLink, this.centered = false});

  final void Function(_FooterAction action) onLink;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final social in FooterSection._socialLinks)
          _SocialIconButton(
            tooltip: social.label,
            icon: social.icon,
            onTap: () => onLink(
              (ctx) => FooterSection.openExternalUrl(ctx, social.url),
            ),
          ),
      ],
    );
  }
}

class _SocialIconButton extends StatefulWidget {
  const _SocialIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_SocialIconButton> createState() => _SocialIconButtonState();
}

class _SocialIconButtonState extends State<_SocialIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(
                color: _hovered ? AppColors.gold.withAlpha(180) : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovered ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLinkData {
  final String label;
  final _FooterAction action;
  const _FooterLinkData(this.label, this.action);
}

class _SocialLink {
  final String label;
  final IconData icon;
  final String url;
  const _SocialLink(this.label, this.icon, this.url);
}
