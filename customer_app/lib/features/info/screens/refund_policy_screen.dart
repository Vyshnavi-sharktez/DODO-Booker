import 'package:flutter/material.dart';

class RefundPolicyScreen extends StatelessWidget {
  final bool inModal;
  const RefundPolicyScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context) {
    const body = _RefundPolicyBody();
    if (inModal) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Refund Policy')),
      body: body,
    );
  }
}

class _RefundPolicyBody extends StatelessWidget {
  const _RefundPolicyBody();

  static const _sections = [
    _PolicySection(
      'Overview',
      'DODO Booker facilitates bookings between customers and service professionals. Refunds are processed according to the cancellation timing and service type described below.',
    ),
    _PolicySection(
      'Cancellation Window',
      'Cancellations made at least 24 hours before the scheduled service time are eligible for a full refund to the original payment method, subject to payment partner processing times.',
    ),
    _PolicySection(
      'Late Cancellations',
      'Cancellations made within 24 hours of the scheduled service may incur a cancellation fee. The applicable fee depends on the service category and will be shown before you confirm cancellation.',
    ),
    _PolicySection(
      'No-Show & Service Issues',
      'If a professional fails to arrive or the service was not delivered as agreed, contact support within 48 hours. We will review your case and may issue a partial or full refund at our discretion.',
    ),
    _PolicySection(
      'Refund Processing',
      'Approved refunds are typically processed within 5–10 business days. The time for funds to appear in your account depends on your bank or payment provider.',
    ),
    _PolicySection(
      'Contact',
      'For refund requests or questions about this policy, contact support@dodobooker.com or visit the Contact Us page in the app.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: _sections.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Last updated: June 2025',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withAlpha(120),
              ),
            ),
          );
        }
        final section = _sections[i - 1];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withAlpha(80), width: 0.8),
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
      },
    );
  }
}

class _PolicySection {
  final String title;
  final String body;
  const _PolicySection(this.title, this.body);
}
