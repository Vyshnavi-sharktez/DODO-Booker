import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/razorpay_checkout.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/subscription_repository.dart';
import '../providers/subscription_provider.dart';

// ── Payment states ─────────────────────────────────────────────────────────────

enum _PaymentStatus { idle, processing, success, failed }

class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({super.key, required this.info});
  final PendingPaymentInfo info;

  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  _PaymentStatus _status = _PaymentStatus.idle;
  String? _errorMessage;
  // Stored so we can validate stale Razorpay callbacks against the current order.
  String? _pendingOrderId;

  PendingPaymentInfo get info => widget.info;

  // ── Razorpay flow ──────────────────────────────────────────────────────────

  Future<void> _startRazorpay() async {
    setState(() {
      _status = _PaymentStatus.processing;
      _errorMessage = null;
    });

    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) {
      setState(() {
        _status = _PaymentStatus.failed;
        _errorMessage = 'Vendor session not found. Please log in again.';
      });
      return;
    }

    // ── Step 1: Create Razorpay order via Edge Function ────────────────────
    Map<String, dynamic> orderData;
    try {
      orderData = await ref.read(subscriptionRepositoryProvider).createSubscriptionOrder(
            subscriptionId: info.subscriptionId,
            paymentId: info.paymentId,
            vendorId: vendor.id,
          );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      await _recordFailure(message);
      setState(() {
        _status = _PaymentStatus.failed;
        _errorMessage = message;
      });
      return;
    }

    final keyId = orderData['key_id'] as String;
    final orderId = orderData['order_id'] as String;
    final amountPaise = (orderData['amount_paise'] as num).toInt();
    _pendingOrderId = orderId;

    // ── Step 2: Open Razorpay checkout ────────────────────────────────────
    _RazorpayResult result;

    if (kIsWeb) {
      final webResult = await openRazorpayCheckout(
        keyId: keyId,
        orderId: orderId,
        amountPaise: amountPaise,
        name: 'DODO Services',
        description: info.planName,
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
      final razorpay = Razorpay();

      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        razorpay.clear();
        if (!completer.isCompleted) {
          if (r.orderId != orderId) {
            completer.complete(_RazorpayResult.failure('Order ID mismatch — stale callback.'));
            return;
          }
          completer.complete(_RazorpayResult.success(
            paymentId: r.paymentId ?? '',
            orderId: r.orderId ?? orderId,
            signature: r.signature ?? '',
          ));
        }
      });

      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        razorpay.clear();
        if (!completer.isCompleted) {
          completer.complete(_RazorpayResult.failure(
            r.message ?? 'Payment failed or was cancelled.',
          ));
        }
      });

      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
        razorpay.clear();
        if (!completer.isCompleted) {
          completer.complete(_RazorpayResult.failure('External wallet is not supported.'));
        }
      });

      razorpay.open({
        'key': keyId,
        'amount': amountPaise,
        'order_id': orderId,
        'currency': 'INR',
        'name': 'DODO Services',
        'description': info.planName,
        'prefill': {'contact': '', 'email': ''},
        'external': {'wallets': <String>[]},
      });

      result = await completer.future;
    }

    if (!result.succeeded) {
      if (!mounted) return;
      await _recordFailure(result.errorMessage ?? 'Payment was not completed.');
      setState(() {
        _status = _PaymentStatus.failed;
        _errorMessage = result.errorMessage ?? 'Payment was not completed.';
      });
      return;
    }

    // ── Step 3: Verify signature server-side — activates subscription ──────
    if (!mounted) return;
    setState(() => _status = _PaymentStatus.processing);

    try {
      await ref.read(subscriptionRepositoryProvider).verifySubscriptionPayment(
            subscriptionId: info.subscriptionId,
            paymentId: info.paymentId,
            vendorId: vendor.id,
            razorpayPaymentId: result.paymentId!,
            razorpayOrderId: result.orderId!,
            razorpaySignature: result.signature!,
          );
      ref.invalidate(mySubscriptionProvider);
      if (mounted) setState(() => _status = _PaymentStatus.success);
    } on FunctionException catch (e) {
      String message = 'Payment received but verification failed.';
      final details = e.details;
      if (details is Map) message = details['error'] as String? ?? message;
      if (!mounted) return;
      setState(() {
        _status = _PaymentStatus.failed;
        _errorMessage = '$message Contact support if the amount was deducted.';
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _status = _PaymentStatus.failed;
        _errorMessage = '$message Contact support if the amount was deducted.';
      });
    }
  }

  Future<void> _recordFailure(String reason) async {
    try {
      await ref.read(subscriptionRepositoryProvider).recordPaymentFailure(
            paymentId: info.paymentId,
            notes: reason,
          );
    } catch (_) {
      // Best-effort; UI shows the failure regardless.
    }
  }

  void _retry() => context.go(RoutePaths.browsePlans);
  void _done() => context.go(RoutePaths.subscription);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      _PaymentStatus.idle => _PayNowView(
          info: info,
          onPayNow: _startRazorpay,
        ),
      _PaymentStatus.processing => const _ProcessingView(),
      _PaymentStatus.success => _SuccessView(
          info: info,
          onDone: _done,
        ),
      _PaymentStatus.failed => _FailedView(
          info: info,
          message: _errorMessage,
          onRetry: _retry,
          onCancel: _done,
        ),
    };
  }
}

// ── Idle: shows amount + Pay Now button ───────────────────────────────────────

class _PayNowView extends StatelessWidget {
  const _PayNowView({required this.info, required this.onPayNow});
  final PendingPaymentInfo info;
  final VoidCallback onPayNow;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amount card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.82),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Icon(Icons.payment_rounded,
                    color: Colors.white70, size: 36),
                const SizedBox(height: 12),
                Text(
                  '₹${info.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.planName,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Pay Now button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPayNow,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.payment_rounded, size: 20),
              label: const Text(
                'Pay Now',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Secure payment note
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Text(
                'Secured by Razorpay',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Processing ─────────────────────────────────────────────────────────────────

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Processing payment…',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Success ────────────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.info, required this.onDone});
  final PendingPaymentInfo info;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  size: 52, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            const Text('Payment Successful!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text(
              'Your ${info.planName} subscription is now active.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Go to My Subscription',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Failed ─────────────────────────────────────────────────────────────────────

class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.info,
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });
  final PendingPaymentInfo info;
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cancel_rounded,
                  size: 52, color: AppColors.error),
            ),
            const SizedBox(height: 24),
            const Text('Payment Failed',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text(
              message ?? 'Payment was not completed. Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try Again',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onCancel,
              child: const Text('Go Back',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
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
        orderId: orderId,
        signature: signature,
      );

  factory _RazorpayResult.failure(String message) =>
      _RazorpayResult._(succeeded: false, errorMessage: message);
}
