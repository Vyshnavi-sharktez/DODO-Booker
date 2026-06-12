import 'package:flutter/material.dart';
import '../../domain/models/transaction.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
