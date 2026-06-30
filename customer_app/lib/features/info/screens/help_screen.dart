import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  final bool inModal;
  const HelpScreen({super.key, this.inModal = false});

  @override
  Widget build(BuildContext context) {
    const body = _HelpBody();
    if (inModal) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: body,
    );
  }
}

class _HelpBody extends StatelessWidget {
  const _HelpBody();

  static const _faqs = [
    _FaqItem(
      'How do I book a service?',
      'Browse categories on the home page, select a service, choose a date and time, and confirm your booking.',
    ),
    _FaqItem(
      'Can I reschedule a booking?',
      'Yes. Open My Bookings, select your booking, and use the reschedule option if available for your service type.',
    ),
    _FaqItem(
      'How do payments work?',
      'You pay securely through the app after confirming your booking details. Final charges may vary based on service scope.',
    ),
    _FaqItem(
      'How do I cancel a booking?',
      'Go to My Bookings, open the booking, and follow the cancellation steps. Refunds depend on our Refund Policy and timing.',
    ),
    _FaqItem(
      'Who do I contact for support?',
      'Use the Contact Us page or email support@dodobooker.com for account, payment, or service-related help.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: _faqs.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Frequently asked questions',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        }
        final faq = _faqs[i - 1];
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
                faq.question,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                faq.answer,
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

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem(this.question, this.answer);
}
