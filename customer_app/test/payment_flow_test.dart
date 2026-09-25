// Regression tests for the Razorpay payment-lifecycle fix.
//
// Behavior under test:
//   1. Definitive failure/dismiss → booking cancelled, cart preserved, no retry
//      against the old booking.  A "Payment Failed" dialog is shown and
//      "Back to Cart" returns the customer to their preserved cart.
//   2. Uncertain outcome (HMAC error, external wallet) → booking preserved,
//      shown with warning banner, NOT in normal Upcoming flow, NOT assignable.
//      No "Payment Failed" dialog — a snackbar is used instead.
//   3. COD bookings are unaffected by all Razorpay guards.
//   4. Successful payment → booking is paid, flows normally.
//
// Widget-level tests for the PaymentFailedDialog widget are in
// payment_failed_dialog_test.dart.
//
// These tests verify model-level semantics (MyBookingModel getters) that the
// fix depends on.  Async flows (gate cancellation, DB trigger) are covered by
// the integration test suite.

import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/my_booking_model.dart';
import 'package:customer_app/models/address_model.dart';

const _base = AddressModel(
  id: '',
  label: 'Home',
  line1: '1 Test Street',
  city: 'Hyderabad',
  state: 'Telangana',
  pincode: '500001',
);

final _date = DateTime(2026, 9, 24, 10, 0);

MyBookingModel _rzpBooking(
  String bookingStatus, {
  String paymentStatus = 'pending',
}) =>
    MyBookingModel(
      id: 'bk-rzp-001',
      serviceId: 'svc-1',
      serviceName: 'AC Service',
      address: _base,
      scheduledDate: _date,
      timeSlot: '10:00 AM',
      baseAmount: 500.0,
      taxAmount: 90.0,
      totalAmount: 590.0,
      status: bookingStatus,
      paymentMethod: 'razorpay',
      paymentStatus: paymentStatus,
      createdAt: _date,
    );

MyBookingModel _codBooking(String bookingStatus) => MyBookingModel(
      id: 'bk-cod-001',
      serviceId: 'svc-1',
      serviceName: 'AC Service',
      address: _base,
      scheduledDate: _date,
      timeSlot: '10:00 AM',
      baseAmount: 500.0,
      taxAmount: 90.0,
      totalAmount: 590.0,
      status: bookingStatus,
      paymentMethod: 'cod',
      createdAt: _date,
    );

void main() {
  // ── Scenario 1 & 2: Definitive payment failure / modal dismissed ─────────────
  // booking_gate / checkout_screen call cancelBooking() and show the
  // PaymentFailedDialog.  Tapping "Back to Cart" returns to the preserved cart.
  group('Definitive payment failure — booking cancelled, dialog shown', () {
    test('cancelled Razorpay booking is not upcoming', () {
      final b = _rzpBooking('cancelled');
      expect(b.isUpcoming, false);
    });

    test('cancelled Razorpay booking is cancelled', () {
      final b = _rzpBooking('cancelled');
      expect(b.isCancelled, true);
    });

    test('cancelled Razorpay booking cannot be cancelled again', () {
      final b = _rzpBooking('cancelled');
      expect(b.canCancel, false);
    });

    test('cancelled Razorpay booking is not ongoing or completed', () {
      final b = _rzpBooking('cancelled');
      expect(b.isOngoing, false);
      expect(b.isCompleted, false);
    });
  });

  // ── Scenario 3: Payment status uncertain (checkout error before SDK opened) ──
  // booking_gate.dart ALSO cancels here (edge function failed, no charge possible).
  // After cancellation the model state is identical to scenarios 1 & 2 above.

  // ── Scenario 4: HMAC verification failure ───────────────────────────────────
  // Razorpay SDK reported 'success' → customer may have been charged.
  // booking_gate.dart does NOT cancel.  Booking stays 'pending'.
  group('HMAC verification failure — booking preserved (uncertain charge)', () {
    test('pending Razorpay booking with unverified payment is upcoming', () {
      final b = _rzpBooking('pending');
      expect(b.isUpcoming, true);
    });

    test('pending Razorpay booking with unverified payment is not cancelled', () {
      final b = _rzpBooking('pending');
      expect(b.isCancelled, false);
    });

    test('customer can cancel a pending Razorpay booking themselves', () {
      final b = _rzpBooking('pending');
      expect(b.canCancel, true);
    });
  });

  // ── Scenario 5: External wallet ──────────────────────────────────────────────
  // Customer redirected to Paytm/etc.; payment may still complete.
  // booking_gate.dart does NOT cancel.  Same model state as scenario 4.
  group('External wallet flow — booking preserved (payment may still complete)', () {
    test('pending Razorpay booking after external wallet redirect is upcoming', () {
      final b = _rzpBooking('pending');
      expect(b.isUpcoming, true);
      expect(b.isCancelled, false);
    });
  });

  // ── Scenario 6: Successful payment ──────────────────────────────────────────
  // SDK success + HMAC verified → payment_status = 'success'.
  group('Successful payment — booking remains upcoming normally', () {
    test('paid Razorpay booking is upcoming', () {
      final b = _rzpBooking('pending', paymentStatus: 'success');
      expect(b.isUpcoming, true);
      expect(b.isCod, false);
    });

    test('paid and assigned Razorpay booking is upcoming', () {
      final b = MyBookingModel(
        id: 'bk-rzp-paid',
        serviceId: 'svc-1',
        serviceName: 'AC Service',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 90.0,
        totalAmount: 590.0,
        status: 'assigned',
        paymentMethod: 'razorpay',
        paymentStatus: 'success',
        createdAt: _date,
      );
      expect(b.isUpcoming, true);
      expect(b.isCancelled, false);
    });
  });

  // ── Scenario 7: COD booking assignment — unaffected ─────────────────────────
  // DB trigger only fires for payment_method IN ('razorpay', 'online').
  // COD bookings have isCod = true and should be assignable regardless of
  // payment_status.
  group('COD booking — unaffected by Razorpay assignment guard', () {
    test('pending COD booking is upcoming', () {
      final b = _codBooking('pending');
      expect(b.isUpcoming, true);
      expect(b.isCod, true);
    });

    test('cash payment method is also COD', () {
      final b = MyBookingModel(
        id: 'bk-cash',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 400.0,
        taxAmount: 0.0,
        totalAmount: 400.0,
        status: 'pending',
        paymentMethod: 'cash',
        createdAt: _date,
      );
      expect(b.isCod, true);
    });

    test('assigned COD booking is upcoming', () {
      final b = _codBooking('assigned');
      expect(b.isUpcoming, true);
    });
  });

  // ── Scenario 8: Unpaid Razorpay booking assignment blocked ───────────────────
  // DB trigger: blocks UPDATE bookings SET status='assigned' when
  //   payment_method IN ('razorpay','online') AND payment_status != 'success'.
  // This is enforced at the DB level and cannot be tested as a Dart unit test.
  // The model properties below confirm that the trigger targets the right bookings.
  group('Assignment guard — payment method classification (trigger targets)', () {
    test('razorpay payment method is not COD (trigger applies)', () {
      final b = _rzpBooking('pending');
      expect(b.isCod, false);
    });

    test('online payment method is not COD (trigger applies)', () {
      final b = MyBookingModel(
        id: 'bk-online',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'pending',
        paymentMethod: 'online',
        paymentStatus: 'pending',
        createdAt: _date,
      );
      expect(b.isCod, false);
    });

    test('cod payment method is COD (trigger does not apply)', () {
      expect(_codBooking('pending').isCod, true);
    });

    test('razorpay with verified payment — trigger should pass', () {
      final b = _rzpBooking('pending', paymentStatus: 'success');
      // payment_status = 'success' satisfies the trigger condition.
      // Model confirms the payment status is readable.
      expect(b.paymentStatus, 'success');
      expect(b.isCod, false);
    });

    test('razorpay with unverified payment — trigger should block assignment', () {
      final b = _rzpBooking('pending', paymentStatus: 'pending');
      // payment_status = 'pending' would trigger the DB guard on assignment.
      expect(b.paymentStatus, 'pending');
      expect(b.isCod, false);
    });

    test('razorpay booking with null payment_status — trigger should block', () {
      final b = MyBookingModel(
        id: 'bk-rzp-null',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'pending',
        paymentMethod: 'razorpay',
        // paymentStatus intentionally omitted (null)
        createdAt: _date,
      );
      expect(b.paymentStatus, isNull);
      expect(b.isCod, false);
      // DB guard: COALESCE(NEW.payment_status, '') <> 'success' → true → blocked.
    });
  });

  // ── My Bookings visibility — full matrix ────────────────────────────────────
  group('My Bookings visibility after payment flow fix', () {
    test('app-cancelled (no payment_status=failed) → not in Upcoming, in Cancelled', () {
      // cancelBooking() called on dismiss/error; DB trigger has not set
      // payment_status='failed'.  Booking lands in the Cancelled tab.
      final b = _rzpBooking('cancelled'); // paymentStatus defaults to 'pending'
      expect(b.isUpcoming, false);
      expect(b.isCancelled, true);
      expect(b.isPaymentFailed, false);
    });

    test('DB-trigger failed payment → in Failed tab, not in Cancelled', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isUpcoming, false);
      expect(b.isCancelled, false);
      expect(b.isPaymentFailed, true);
    });

    test('successful payment → in Upcoming', () {
      final b = _rzpBooking('pending', paymentStatus: 'success');
      expect(b.isUpcoming, true);
    });

    test('uncertain status (HMAC / external_wallet) → still in Upcoming', () {
      // These cases intentionally preserve the booking for manual investigation.
      final b = _rzpBooking('pending');
      expect(b.isUpcoming, true);
    });

    test('COD pending booking → always in Upcoming', () {
      final b = _codBooking('pending');
      expect(b.isUpcoming, true);
    });

    test('COD pending booking is not in Cancelled', () {
      final b = _codBooking('pending');
      expect(b.isCancelled, false);
    });
  });

  // ── isPaymentUncertain getter ─────────────────────────────────────────────────
  // Drives the warning banner in the Upcoming tab and the admin assignment filter.
  // True when: !isCod AND status=pending AND paymentStatus != 'success'.
  group('isPaymentUncertain — uncertain-payment detection', () {
    test('pending online with payment_status=pending → uncertain', () {
      expect(_rzpBooking('pending').isPaymentUncertain, true);
    });

    test('pending online with payment_status=failed → uncertain', () {
      expect(_rzpBooking('pending', paymentStatus: 'failed').isPaymentUncertain, true);
    });

    test('pending online with null payment_status → uncertain', () {
      final b = MyBookingModel(
        id: 'bk-null-ps',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'pending',
        paymentMethod: 'online',
        createdAt: _date,
      );
      expect(b.isPaymentUncertain, true);
    });

    test('pending online with payment_status=success → NOT uncertain', () {
      expect(_rzpBooking('pending', paymentStatus: 'success').isPaymentUncertain, false);
    });

    test('COD pending → NOT uncertain', () {
      expect(_codBooking('pending').isPaymentUncertain, false);
    });

    test('cash payment method → NOT uncertain', () {
      final b = MyBookingModel(
        id: 'bk-cash-2',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 400.0,
        taxAmount: 0.0,
        totalAmount: 400.0,
        status: 'pending',
        paymentMethod: 'cash',
        createdAt: _date,
      );
      expect(b.isPaymentUncertain, false);
    });

    test('cancelled online booking → NOT uncertain (wrong status)', () {
      expect(_rzpBooking('cancelled').isPaymentUncertain, false);
    });

    test('uncertain booking → isUpcoming still true (needed for canCancel)', () {
      // isUpcoming must remain true so the customer can cancel an uncertain booking.
      final b = _rzpBooking('pending');
      expect(b.isPaymentUncertain, true);
      expect(b.isUpcoming, true);
      expect(b.canCancel, true);
    });

    test('uncertain booking → COD is false (admin isPaymentUnverified mirrors this)', () {
      final b = _rzpBooking('pending');
      expect(b.isPaymentUncertain, true);
      expect(b.isCod, false);
    });
  });

  // ── Checkout cancellation semantics ───────────────────────────────────────────
  // Verifies model state after the checkout/cancel paths in booking_gate.dart
  // and checkout_screen.dart.
  group('Checkout cancellation — model state after failure paths', () {
    test('after definitive failure: booking is cancelled', () {
      // booking_gate / checkout_screen cancels on failure/dismiss.
      // Customer retries by going back to cart — a fresh booking is created.
      final b = _rzpBooking('cancelled');
      expect(b.isCancelled, true);
      expect(b.isUpcoming, false);
      expect(b.canCancel, false);
    });

    test('fresh retry booking has a different ID from the failed one', () {
      final failed = _rzpBooking('cancelled');
      final retried = MyBookingModel(
        id: 'bk-rzp-002', // new booking created by fresh checkout
        serviceId: 'svc-1',
        serviceName: 'AC Service',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 90.0,
        totalAmount: 590.0,
        status: 'pending',
        paymentMethod: 'razorpay',
        paymentStatus: 'success',
        createdAt: _date,
      );
      expect(retried.id, isNot(equals(failed.id)));
      expect(retried.isPaymentUncertain, false);
      expect(retried.isUpcoming, true);
    });

    test('uncertain booking (verifyPayment threw) — preserved, no cancel', () {
      // verifyPayment failure: customer may have been charged.
      // Booking stays pending, no cancellation, shown with warning banner.
      final b = _rzpBooking('pending');
      expect(b.isPaymentUncertain, true);
      expect(b.isCancelled, false);
      expect(b.isUpcoming, true);
    });

    test('uncertain booking → isPaymentUncertain=true, still shown in Upcoming inline', () {
      // The UI no longer separates uncertain bookings with a banner;
      // they appear inline in Upcoming until the outcome is resolved.
      // isPaymentUncertain is still used by the admin panel and can be
      // surfaced in future UI iterations.
      final b = _rzpBooking('pending');
      expect(b.isPaymentUncertain, true);
      expect(b.isUpcoming, true);
      expect(b.isPaymentFailed, false);
    });

    test('after successful verification: booking is normal upcoming', () {
      final b = _rzpBooking('pending', paymentStatus: 'success');
      expect(b.isPaymentUncertain, false);
      expect(b.isUpcoming, true);
      final isNormalUpcoming = b.isUpcoming && !b.isPaymentUncertain;
      expect(isNormalUpcoming, true);
    });

    test('COD booking is never uncertain, always normal upcoming', () {
      final b = _codBooking('pending');
      expect(b.isPaymentUncertain, false);
      expect(b.isCod, true);
      final isNormalUpcoming = b.isUpcoming && !b.isPaymentUncertain;
      expect(isNormalUpcoming, true);
    });
  });

  // ── DB auto-cancel trigger / backfill migration outcome ─────────────────────
  // Migration 20260924000005 sets status='cancelled' + payment_status='failed'
  // on stale pending online bookings.  The trigger fires the same transition
  // in real-time when booking_payments.status flips to 'failed'.
  // Model properties verify the row lands in the Failed tab, not Cancelled.
  group('DB trigger / backfill outcome — status=cancelled payment_status=failed', () {
    test('backfill result: not upcoming', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isUpcoming, false);
    });

    test('backfill result: isPaymentFailed (not isCancelled)', () {
      // These go to the Failed tab, not the Cancelled tab.
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isPaymentFailed, true);
      expect(b.isCancelled, false);
    });

    test('backfill result: not payment uncertain', () {
      // status != 'pending' → isPaymentUncertain = false regardless of paymentStatus.
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isPaymentUncertain, false);
    });

    test('backfill result: can rebook', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.canRebook, true);
    });

    test('backfill result: cannot cancel again', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.canCancel, false);
    });

    test('trigger does not affect successful payment — still upcoming', () {
      // booking_payments.status='success' never triggers the cancel function.
      // Booking stays status='pending' (or 'assigned') with payment_status='success'.
      final b = _rzpBooking('pending', paymentStatus: 'success');
      expect(b.isUpcoming, true);
      expect(b.isCancelled, false);
      expect(b.isPaymentFailed, false);
      expect(b.isPaymentUncertain, false);
    });

    test('trigger does not affect COD — isCod is true, no trigger applies', () {
      // DB trigger checks payment_method IN (razorpay, online) so COD is skipped.
      final b = _codBooking('pending');
      expect(b.isCod, true);
      expect(b.isUpcoming, true);
      expect(b.isCancelled, false);
      expect(b.isPaymentFailed, false);
    });
  });

  // ── isPaymentFailed getter — Failed tab routing ──────────────────────────────
  // A booking is isPaymentFailed when: !isCod && status='cancelled' &&
  // paymentStatus='failed'.  This is the state set by the DB auto-cancel trigger
  // and the backfill migration.  These bookings appear only in the Failed tab.
  group('isPaymentFailed — Failed tab routing', () {
    test('cancelled + payment_status=failed → isPaymentFailed', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isPaymentFailed, true);
    });

    test('isPaymentFailed → isCancelled is false (not in Cancelled tab)', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isCancelled, false);
    });

    test('isPaymentFailed → canRebook is true (cart preserved, retry allowed)', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.canRebook, true);
    });

    test('isPaymentFailed → not upcoming, not ongoing, not completed', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isUpcoming, false);
      expect(b.isOngoing, false);
      expect(b.isCompleted, false);
    });

    test('isPaymentFailed → canCancel is false', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.canCancel, false);
    });

    test('isPaymentFailed → isPaymentUncertain is false', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isPaymentUncertain, false);
    });

    test('cancelled + payment_status=pending → NOT isPaymentFailed (in Cancelled)', () {
      final b = _rzpBooking('cancelled'); // paymentStatus defaults to 'pending'
      expect(b.isPaymentFailed, false);
      expect(b.isCancelled, true);
    });

    test('cancelled + payment_status=null → NOT isPaymentFailed', () {
      final b = MyBookingModel(
        id: 'bk-null-cancelled',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'cancelled',
        paymentMethod: 'online',
        // paymentStatus null
        createdAt: _date,
      );
      expect(b.isPaymentFailed, false);
      expect(b.isCancelled, true);
    });

    test('COD cancelled → NOT isPaymentFailed (isCod=true excludes it)', () {
      final b = _codBooking('cancelled');
      expect(b.isPaymentFailed, false);
      expect(b.isCancelled, true);
    });

    test('pending + payment_status=failed → NOT isPaymentFailed (wrong status)', () {
      // DB trigger hasn't fired yet; booking is still pending.
      final b = _rzpBooking('pending', paymentStatus: 'failed');
      expect(b.isPaymentFailed, false);
      expect(b.isPaymentUncertain, true); // still uncertain until cancelled
    });

    test('completed online booking → NOT isPaymentFailed', () {
      final b = MyBookingModel(
        id: 'bk-rzp-done',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'completed',
        paymentMethod: 'razorpay',
        paymentStatus: 'success',
        createdAt: _date,
      );
      expect(b.isPaymentFailed, false);
    });
  });

  // ── _PaymentFailedInfoBanner gate — booking_details_screen.dart ──────────────
  // The banner is conditionally rendered: `if (booking.isPaymentFailed)`.
  // These model-level checks verify the exact cases where it should and should
  // not appear, without requiring a full widget test of the details screen.
  group('_PaymentFailedInfoBanner — display gate (model level)', () {
    test('isPaymentFailed=true → banner should be shown', () {
      final b = _rzpBooking('cancelled', paymentStatus: 'failed');
      expect(b.isPaymentFailed, true);
    });

    test('regular cancellation (no payment_status=failed) → banner NOT shown', () {
      final b = _rzpBooking('cancelled'); // paymentStatus='pending'
      expect(b.isPaymentFailed, false);
    });

    test('uncertain payment (status=pending) → banner NOT shown', () {
      final b = _rzpBooking('pending');
      expect(b.isPaymentFailed, false);
    });

    test('COD cancelled → banner NOT shown (isCod excludes isPaymentFailed)', () {
      final b = _codBooking('cancelled');
      expect(b.isPaymentFailed, false);
    });

    test('successful payment → banner NOT shown', () {
      final b = _rzpBooking('pending', paymentStatus: 'success');
      expect(b.isPaymentFailed, false);
    });

    test('isPaymentFailed and isCancelled are mutually exclusive', () {
      // Ensures the banner and the cancellation path never both render.
      final failed = _rzpBooking('cancelled', paymentStatus: 'failed');
      final cancelled = _rzpBooking('cancelled'); // payment_status=pending
      expect(failed.isPaymentFailed, true);
      expect(failed.isCancelled, false);
      expect(cancelled.isPaymentFailed, false);
      expect(cancelled.isCancelled, true);
    });
  });

  // ── paymentStatusBadgeLabel — My Bookings card payment badge ────────────────
  group('paymentStatusBadgeLabel — booking card payment badge text', () {
    test('online payment_status=pending → Payment Pending', () {
      expect(_rzpBooking('pending').paymentStatusBadgeLabel, 'Payment Pending');
    });

    test('online payment_status=null → Payment Pending', () {
      final b = MyBookingModel(
        id: 'bk-null-badge',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'pending',
        paymentMethod: 'online',
        // paymentStatus omitted (null)
        createdAt: _date,
      );
      expect(b.paymentStatusBadgeLabel, 'Payment Pending');
    });

    test('online payment_status=failed → Payment Failed', () {
      expect(_rzpBooking('pending', paymentStatus: 'failed').paymentStatusBadgeLabel, 'Payment Failed');
    });

    test('online payment_status=success → Paid', () {
      expect(_rzpBooking('pending', paymentStatus: 'success').paymentStatusBadgeLabel, 'Paid');
    });

    test('online success on assigned booking → Paid', () {
      final b = MyBookingModel(
        id: 'bk-assigned-paid',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 500.0,
        taxAmount: 0.0,
        totalAmount: 500.0,
        status: 'assigned',
        paymentMethod: 'online',
        paymentStatus: 'success',
        createdAt: _date,
      );
      expect(b.paymentStatusBadgeLabel, 'Paid');
    });

    test('COD booking → null (no online payment badge)', () {
      expect(_codBooking('pending').paymentStatusBadgeLabel, isNull);
    });

    test('cash payment method → null', () {
      final b = MyBookingModel(
        id: 'bk-cash-badge',
        serviceId: 'svc-1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _date,
        timeSlot: '10:00 AM',
        baseAmount: 400.0,
        taxAmount: 0.0,
        totalAmount: 400.0,
        status: 'pending',
        paymentMethod: 'cash',
        createdAt: _date,
      );
      expect(b.paymentStatusBadgeLabel, isNull);
    });
  });

}
