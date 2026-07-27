import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
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

  PendingPaymentInfo get info => widget.info;

  // ── Simulate payment success (placeholder) ─────────────────────────────────
  //
  // When integrating Razorpay:
  //   1. Replace this method body with `gateway.initiatePayment(request)`.
  //   2. On PaymentResult.success = true → call _onPaymentSuccess(reference).
  //   3. On PaymentResult.success = false → call _onPaymentFailed(errorMsg).
  //   4. Remove the simulate buttons from the build method.

  Future<void> _onPaymentSuccess([String? gatewayRef]) async {
    setState(() => _status = _PaymentStatus.processing);
    try {
      await ref.read(subscriptionRepositoryProvider).activateSubscription(
            subscriptionId: info.subscriptionId,
            paymentId: info.paymentId,
            planDurationDays: info.planDurationDays,
            gatewayReference: gatewayRef,
          );
      ref.invalidate(mySubscriptionProvider);
      if (mounted) setState(() => _status = _PaymentStatus.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _PaymentStatus.failed;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _onPaymentFailed([String? reason]) async {
    setState(() => _status = _PaymentStatus.processing);
    try {
      await ref.read(subscriptionRepositoryProvider).recordPaymentFailure(
            paymentId: info.paymentId,
            notes: reason,
          );
    } catch (_) {
      // Best-effort; failure to record is logged but does not block UI.
    }
    if (mounted) {
      setState(() {
        _status = _PaymentStatus.failed;
        _errorMessage = reason ?? 'Payment was not completed.';
      });
    }
  }

  void _retry() {
    // Navigate back to browse plans to select a plan again.
    // The pending_payment subscription + failed payment stay in DB;
    // the unique index prevents creating a second pending subscription.
    // A full retry flow would create a new payment record for the same
    // subscription — handled by SubscriptionRepository.createRetryPayment().
    context.go(RoutePaths.browsePlans);
  }

  void _done() => context.go(RoutePaths.subscription);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return VendorScaffold(
      title: 'Payment',
      child: switch (_status) {
        _PaymentStatus.idle => _IdleView(
            info: info,
            onSimulateSuccess: () => _onPaymentSuccess('SIMULATE_OK'),
            onSimulateFail: () => _onPaymentFailed('Simulated payment failure'),
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
      },
    );
  }
}

// ── Idle: shows payment details + simulate buttons ─────────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.info,
    required this.onSimulateSuccess,
    required this.onSimulateFail,
  });
  final PendingPaymentInfo info;
  final VoidCallback onSimulateSuccess;
  final VoidCallback onSimulateFail;

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
                  AppColors.primary.withValues(alpha: 0.82)
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
          const SizedBox(height: 24),

          // Placeholder notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Payment gateway integration is in progress. '
                    'Use the simulate buttons below to test the flow.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSimulateSuccess,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: const Text('Simulate Payment Success',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSimulateFail,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Simulate Payment Failure',
                  style: TextStyle(fontSize: 14)),
            ),
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
              width: 88, height: 88,
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
              width: 88, height: 88,
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
