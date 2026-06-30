import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  final bool inModal;
  const PrivacyPolicyScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context) {
    final body = _PolicyBody(
      sections: _privacySections,
      lastUpdated: 'June 2025',
    );
    if (inModal) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: body,
    );
  }
}

// ── Terms & Conditions ────────────────────────────────────────────────────────

class TermsScreen extends StatelessWidget {
  final bool inModal;
  const TermsScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context) {
    final body = _PolicyBody(
      sections: _termsSections,
      lastUpdated: 'June 2025',
    );
    if (inModal) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: body,
    );
  }
}

// ── Shared policy body ────────────────────────────────────────────────────────

class _PolicyBody extends StatelessWidget {
  final List<_PolicySection> sections;
  final String lastUpdated;

  const _PolicyBody({required this.sections, required this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: sections.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Last updated: $lastUpdated',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withAlpha(120),
              ),
            ),
          );
        }
        final section = sections[i - 1];
        return _SectionCard(section: section);
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _PolicySection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(80), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withAlpha(180),
              height: 1.65,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _PolicySection {
  final String title;
  final String body;
  const _PolicySection(this.title, this.body);
}

const _privacySections = [
  _PolicySection(
    'Information We Collect',
    'We collect information you provide directly to us, such as your name, phone number, email address, and location. We also collect information about your bookings and usage of our services.',
  ),
  _PolicySection(
    'How We Use Your Information',
    'We use the information we collect to provide, maintain, and improve our services, process your bookings, send you service-related communications, and ensure your account security.',
  ),
  _PolicySection(
    'Information Sharing',
    'We share your information with service professionals only as necessary to fulfil your bookings. We do not sell your personal information to third parties. We may share anonymised, aggregated data for analytics purposes.',
  ),
  _PolicySection(
    'Data Security',
    'We implement industry-standard security measures to protect your personal information. All data is encrypted in transit and at rest. We regularly review and update our security practices.',
  ),
  _PolicySection(
    'Your Rights',
    'You have the right to access, correct, or delete your personal information. You may also request a copy of the data we hold about you. Contact us through the app to exercise these rights.',
  ),
  _PolicySection(
    'Cookies & Analytics',
    'We use cookies and similar technologies to improve your experience, analyse usage patterns, and deliver personalised content. You can control cookie preferences through your device settings.',
  ),
  _PolicySection(
    'Contact Us',
    'If you have any questions about this Privacy Policy, please contact our support team through the DODO Booker app or write to us at privacy@dodobooker.com.',
  ),
];

const _termsSections = [
  _PolicySection(
    'Acceptance of Terms',
    'By using DODO Booker, you agree to these Terms & Conditions. If you do not agree, please do not use our services. We may update these terms from time to time, and continued use constitutes acceptance.',
  ),
  _PolicySection(
    'Use of Services',
    'DODO Booker provides a platform to connect customers with home service professionals. You agree to use our services only for lawful purposes and in accordance with these terms.',
  ),
  _PolicySection(
    'Account Responsibility',
    'You are responsible for maintaining the confidentiality of your account and for all activities that occur under your account. Please notify us immediately of any unauthorised use.',
  ),
  _PolicySection(
    'Booking & Payments',
    'All bookings are subject to professional availability. Prices displayed are estimates; final charges may vary. Payments are processed securely through our payment partners.',
  ),
  _PolicySection(
    'Cancellations & Refunds',
    'Cancellation policies vary by service type and timing. Refunds are processed in accordance with our Refund Policy, which is available in the Help section of the app.',
  ),
  _PolicySection(
    'Limitation of Liability',
    'DODO Booker acts as a marketplace facilitator and is not liable for the quality or outcome of services provided by professionals. We facilitate connections but do not directly provide the services.',
  ),
  _PolicySection(
    'Governing Law',
    'These terms are governed by the laws of India. Any disputes arising from the use of DODO Booker services shall be subject to the jurisdiction of the courts in India.',
  ),
];
