import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../../core/services/razorpay_checkout.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/wallet_provider.dart';

// barrierDismissible=false prevents accidental tap-outside dismissal during
// payment. The × button is always enabled so the user can always escape.
void showTopUpDialog(
  BuildContext context, {
  required String vendorId,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => TopUpDialog(vendorId: vendorId),
  );
}

class TopUpDialog extends ConsumerStatefulWidget {
  const TopUpDialog({
    super.key,
    required this.vendorId,
  });

  final String vendorId;

  @override
  ConsumerState<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends ConsumerState<TopUpDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '1000');
  bool _isSubmitting = false;

  // Stored so dispose() can call clear() if the dialog is closed while
  // Razorpay is mid-flight (prevents stale callbacks on the next open).
  Razorpay? _razorpay;

  static const _presetAmounts = [500.0, 1000.0, 2000.0, 5000.0];

  @override
  void dispose() {
    _razorpay?.clear();
    _amountController.dispose();
    super.dispose();
  }

  void _selectPreset(double amount) {
    setState(() => _amountController.text = amount.toInt().toString());
  }

  // ── Entry point ───────────────────────────────────────────────────────────
  // The try/finally guarantees _isSubmitting is always reset, even if an
  // unexpected exception escapes _doTopUp (cast failure, network error, etc.).

  Future<void> _startTopUp() async {
    if (!_formKey.currentState!.validate()) return;

    final amountRupees = double.tryParse(_amountController.text.trim());
    if (amountRupees == null || amountRupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount greater than 0')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _doTopUp(amountRupees);
    } catch (e) {
      debugPrint('[WalletTopUp] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // Reset even if the dialog was already popped (mounted guard prevents
      // calling setState on a disposed widget).
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Payment flow ─────────────────────────────────────────────────────────
  // Throws Exception with a user-readable message on any failure.
  // Returns normally only after the wallet has been credited server-side.

  Future<void> _doTopUp(double amountRupees) async {
    // ── Step 1: Create Razorpay order ──────────────────────────────────────
    final orderData = await ref
        .read(walletRepositoryProvider)
        .createTopUpOrder(vendorId: widget.vendorId, amountRupees: amountRupees);

    // These casts are inside the try block so a malformed response throws a
    // caught Exception rather than leaking past the finally.
    final attemptId = orderData['attempt_id'] as String;
    final keyId     = orderData['key_id']      as String;
    final orderId   = orderData['order_id']    as String;
    final amountPaise = (orderData['amount_paise'] as num).toInt();

    debugPrint('[WalletTopUp] Order created — attemptId=$attemptId orderId=$orderId amount=${amountPaise}p');

    // ── Step 2: Open Razorpay checkout ─────────────────────────────────────
    _RazorpayResult result;

    if (kIsWeb) {
      final webResult = await openRazorpayCheckout(
        keyId: keyId,
        orderId: orderId,
        amountPaise: amountPaise,
        name: 'DODO Services',
        description: 'Wallet Top-Up',
      );
      result = webResult.succeeded
          ? _RazorpayResult.success(
              paymentId: webResult.paymentId!,
              orderId: webResult.orderId!,
              signature: webResult.signature!,
            )
          : _RazorpayResult.failure(
              webResult.errorMessage ?? 'Payment was not completed.',
            );
    } else {
      final completer = Completer<_RazorpayResult>();
      _razorpay = Razorpay();

      void clearRazorpay() {
        _razorpay?.clear();
        _razorpay = null;
      }

      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        debugPrint('[WalletTopUp] Payment success — paymentId=${r.paymentId} orderId=${r.orderId}');
        clearRazorpay();
        if (completer.isCompleted) return;
        if (r.orderId != null && r.orderId != orderId) {
          debugPrint('[WalletTopUp] ⚠ orderId mismatch — expected $orderId got ${r.orderId}');
          completer.complete(_RazorpayResult.failure('Order ID mismatch — stale callback.'));
          return;
        }
        completer.complete(_RazorpayResult.success(
          paymentId: r.paymentId ?? '',
          orderId:   r.orderId   ?? orderId,
          signature: r.signature ?? '',
        ));
      });

      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        debugPrint('[WalletTopUp] Payment error — code=${r.code} message=${r.message}');
        clearRazorpay();
        if (!completer.isCompleted) {
          completer.complete(_RazorpayResult.failure(r.message ?? 'Payment cancelled.'));
        }
      });

      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
        debugPrint('[WalletTopUp] External wallet — ${r.walletName}');
        clearRazorpay();
        if (!completer.isCompleted) {
          completer.complete(_RazorpayResult.failure('External wallet not supported.'));
        }
      });

      _razorpay!.open({
        'key':         keyId,
        'amount':      amountPaise,
        'order_id':    orderId,
        'currency':    'INR',
        'name':        'DODO Services',
        'description': 'Wallet Top-Up',
        'prefill':     {'contact': '', 'email': ''},
        'external':    {'wallets': <String>[]},
      });

      result = await completer.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          clearRazorpay();
          return _RazorpayResult.failure('Payment session timed out. Please try again.');
        },
      );
    }

    if (!result.succeeded) {
      throw Exception(result.errorMessage ?? 'Payment was not completed.');
    }

    debugPrint('[WalletTopUp] Signature received — verifying server-side…');

    // ── Step 3: Verify signature and credit wallet ─────────────────────────
    await ref.read(walletRepositoryProvider).verifyTopUp(
      topupAttemptId:    attemptId,
      vendorId:          widget.vendorId,
      razorpayPaymentId: result.paymentId!,
      razorpayOrderId:   result.orderId!,
      razorpaySignature: result.signature!,
    );

    debugPrint('[WalletTopUp] Wallet credited successfully.');

    // ── Step 4: Refresh wallet UI and close ───────────────────────────────
    ref.invalidate(walletProvider(widget.vendorId));
    ref.invalidate(walletTransactionsProvider(widget.vendorId));

    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '₹${amountRupees.toStringAsFixed(2)} added to your wallet.',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Top Up Wallet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Add funds to your prepaid balance',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // × is always tappable — never disabled by _isSubmitting.
                    // Ensures the user is never trapped if the flow hangs.
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.border),
                const SizedBox(height: 16),

                // Amount field
                const Text(
                  'Enter Top-Up Amount (₹)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    prefixText: '₹ ',
                    hintText: 'e.g. 1000',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Top-up amount is required';
                    }
                    final numVal = double.tryParse(val.trim());
                    if (numVal == null || numVal <= 0) {
                      return 'Enter a valid amount greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Preset chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presetAmounts.map((preset) {
                    final isSelected =
                        _amountController.text == preset.toInt().toString();
                    return ChoiceChip(
                      label: Text('₹${preset.toInt()}'),
                      selected: isSelected,
                      onSelected: (_) => _selectPreset(preset),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Cancel is always enabled — same reason as ×.
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _startTopUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(160, 44),
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payment_rounded, size: 18),
                      label: Text(_isSubmitting ? 'Processing…' : 'Add Money'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Internal result type ──────────────────────────────────────────────────────

class _RazorpayResult {
  final bool succeeded;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorMessage;

  const _RazorpayResult._({
    required this.succeeded,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorMessage,
  });

  factory _RazorpayResult.success({
    required String paymentId,
    required String orderId,
    required String signature,
  }) =>
      _RazorpayResult._(
        succeeded: true,
        paymentId: paymentId,
        orderId:   orderId,
        signature: signature,
      );

  factory _RazorpayResult.failure(String message) =>
      _RazorpayResult._(succeeded: false, errorMessage: message);
}
