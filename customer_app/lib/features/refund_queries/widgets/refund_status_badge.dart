import 'package:flutter/material.dart';
import '../models/customer_refund_model.dart';

class RefundStatusBadge extends StatelessWidget {
  const RefundStatusBadge({super.key, required this.refund});

  final CustomerRefundModel refund;

  @override
  Widget build(BuildContext context) {
    final color = refund.statusColor(context);
    final bg = refund.statusBgColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        refund.statusLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
