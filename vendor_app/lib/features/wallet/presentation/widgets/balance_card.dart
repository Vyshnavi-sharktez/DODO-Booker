import 'package:flutter/material.dart';
import '../../domain/models/wallet.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
