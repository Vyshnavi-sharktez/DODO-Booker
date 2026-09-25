import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/booking/widgets/payment_failed_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PaymentFailedDialog — widget', () {
    testWidgets('shows title and message', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));

      final ctx = tester.element(find.byType(SizedBox));
      bool called = false;
      unawaited(showPaymentFailedDialog(ctx, onBackToCart: () => called = true));
      await tester.pumpAndSettle();

      expect(find.text('Payment Failed'), findsOneWidget);
      expect(
        find.text(
          'Your items are still in your cart. '
          "You can try again whenever you're ready.",
        ),
        findsOneWidget,
      );
      expect(find.text('Back to Cart'), findsOneWidget);
      expect(called, false); // callback not invoked yet
    });

    testWidgets('Back to Cart button invokes onBackToCart and closes dialog',
        (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));

      final ctx = tester.element(find.byType(SizedBox));
      bool called = false;
      unawaited(
        showPaymentFailedDialog(ctx, onBackToCart: () => called = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to Cart'));
      await tester.pumpAndSettle();

      expect(called, true);
      // Dialog should be dismissed.
      expect(find.text('Payment Failed'), findsNothing);
    });

    testWidgets('dialog is not dismissible by tapping barrier', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));

      final ctx = tester.element(find.byType(SizedBox));
      unawaited(showPaymentFailedDialog(ctx, onBackToCart: () {}));
      await tester.pumpAndSettle();

      // Tap outside the dialog (barrier area).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Dialog still visible — barrierDismissible=false.
      expect(find.text('Payment Failed'), findsOneWidget);
    });

    testWidgets('error icon is shown', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox()));

      final ctx = tester.element(find.byType(SizedBox));
      unawaited(showPaymentFailedDialog(ctx, onBackToCart: () {}));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });

  // ── Model-level contract for when the dialog is shown vs not shown ───────────
  //
  // showPaymentFailedDialog is shown when:
  //   - booking_gate / checkout_screen encounters a DEFINITIVE failure
  //     (launchCheckout throws OR result.status != 'success')
  //   → the booking is CANCELLED, cart is preserved, isPaymentUncertain=false
  //
  // showPaymentFailedDialog is NOT shown when:
  //   - result.status == 'external_wallet'  (payment may complete in wallet app)
  //   - verifyPayment throws                (customer may already be charged)
  //   → the booking is PRESERVED (status=pending), isPaymentUncertain=true
  //   → a warning banner is shown in My Bookings instead
  //
  // The model state that drives this distinction is tested in payment_flow_test.dart.
}
