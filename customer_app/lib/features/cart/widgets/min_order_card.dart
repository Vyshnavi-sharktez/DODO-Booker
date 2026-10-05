import 'package:flutter/material.dart';

/// Inline minimum-order status card shown above the checkout/place-booking button.
/// Displays a green "ready" state when [effectiveMinimum] is null (all minimums
/// met), or a red warning with shortfall when [effectiveMinimum] is non-null.
class MinOrderCard extends StatelessWidget {
  const MinOrderCard({
    super.key,
    required this.effectiveMinimum,
    required this.currentTotal,
  });

  final double? effectiveMinimum;
  final double currentTotal;

  @override
  Widget build(BuildContext context) {
    if (effectiveMinimum == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF2E7D32)),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                "Minimum order reached. You're ready to checkout.",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E7D32),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final minAmt = effectiveMinimum!;
    final shortfall = (minAmt - currentTotal).ceil();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_rounded, size: 18, color: Color(0xFFE53935)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Minimum order not reached',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                    height: 1.4,
                  ),
                ),
                Text(
                  'Add ₹$shortfall more to continue.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE53935),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current total',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9E9E),
                                height: 1.4),
                          ),
                          Text(
                            '₹${currentTotal.toInt()}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9E9E),
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Minimum order',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9E9E),
                                height: 1.4),
                          ),
                          Text(
                            '₹${minAmt.toInt()}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9E9E),
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
