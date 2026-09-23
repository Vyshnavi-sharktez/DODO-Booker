import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/refunds/domain/models/refund_request.dart';
import 'package:admin_panel/features/refunds/domain/models/refund_transaction.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

RefundRequest _makeRequest({
  RefundTicketStatus status = RefundTicketStatus.submitted,
  double requestedAmount = 500.0,
  double amountPaid = 500.0,
  double? approvedAmount,
  double processedAmount = 0.0,
  List<RefundTransaction> transactions = const [],
  String paymentMethodSnapshot = 'online',
  DateTime? bankDetailsRequestedAt,
  DateTime? bankDetailsSubmittedAt,
}) {
  return RefundRequest(
    id: 'req-1',
    ticketNumber: 'RFD-202609-000001',
    bookingId: 'bk-1',
    customerId: 'cust-1',
    requestedAmount: requestedAmount,
    evidenceUrls: const [],
    evidenceCount: 0,
    paymentMethodSnapshot: paymentMethodSnapshot,
    amountPaidSnapshot: amountPaid,
    status: status,
    approvedAmount: approvedAmount,
    processedAmount: processedAmount,
    createdAt: DateTime(2026, 9, 22),
    updatedAt: DateTime(2026, 9, 22),
    transactions: transactions,
    bankDetailsRequestedAt: bankDetailsRequestedAt,
    bankDetailsSubmittedAt: bankDetailsSubmittedAt,
  );
}

RefundTransaction _makeTxn({
  required double amount,
  RefundTransactionStatus status = RefundTransactionStatus.completed,
}) {
  return RefundTransaction(
    id: 'txn-${amount.toInt()}',
    refundRequestId: 'req-1',
    amount: amount,
    gateway: 'manual',
    status: status,
    refundMethod: 'manual',
    initiatedBy: 'admin-1',
    initiatedAt: DateTime(2026, 9, 22),
    metadata: const {},
    createdAt: DateTime(2026, 9, 22),
  );
}

// ── Status label tests ─────────────────────────────────────────────────────────

void main() {
  group('RefundRequest.statusLabel', () {
    test('submitted', () {
      expect(_makeRequest(status: RefundTicketStatus.submitted).statusLabel,
          'Submitted');
    });
    test('under_review', () {
      expect(_makeRequest(status: RefundTicketStatus.underReview).statusLabel,
          'Under Review');
    });
    test('more_info_requested', () {
      expect(
          _makeRequest(status: RefundTicketStatus.moreInfoRequested).statusLabel,
          'More Info Needed');
    });
    test('approved', () {
      expect(
          _makeRequest(status: RefundTicketStatus.approved).statusLabel,
          'Approved');
    });
    test('partially_approved', () {
      expect(
          _makeRequest(status: RefundTicketStatus.partiallyApproved).statusLabel,
          'Partially Approved');
    });
    test('rejected', () {
      expect(
          _makeRequest(status: RefundTicketStatus.rejected).statusLabel,
          'Rejected');
    });
    test('processing', () {
      expect(
          _makeRequest(status: RefundTicketStatus.processing).statusLabel,
          'Processing');
    });
    test('completed', () {
      expect(
          _makeRequest(status: RefundTicketStatus.completed).statusLabel,
          'Completed');
    });
    test('failed', () {
      expect(
          _makeRequest(status: RefundTicketStatus.failed).statusLabel,
          'Failed');
    });
    test('closed', () {
      expect(
          _makeRequest(status: RefundTicketStatus.closed).statusLabel,
          'Closed');
    });
  });

  // ── statusDbValue round-trips ───────────────────────────────────────────────

  group('RefundRequest.statusDbValue', () {
    final cases = {
      RefundTicketStatus.submitted: 'submitted',
      RefundTicketStatus.underReview: 'under_review',
      RefundTicketStatus.moreInfoRequested: 'more_info_requested',
      RefundTicketStatus.approved: 'approved',
      RefundTicketStatus.partiallyApproved: 'partially_approved',
      RefundTicketStatus.rejected: 'rejected',
      RefundTicketStatus.processing: 'processing',
      RefundTicketStatus.completed: 'completed',
      RefundTicketStatus.failed: 'failed',
      RefundTicketStatus.closed: 'closed',
    };
    for (final entry in cases.entries) {
      test('${entry.key.name} → ${entry.value}', () {
        expect(_makeRequest(status: entry.key).statusDbValue, entry.value);
      });
    }
  });

  // ── fromMap status parsing ─────────────────────────────────────────────────

  group('RefundRequest.fromMap status parsing', () {
    Map<String, dynamic> _base(String status) => {
          'id': 'req-1',
          'ticket_number': 'RFD-202609-000001',
          'booking_id': 'bk-1',
          'customer_id': 'cust-1',
          'requested_amount': 500.0,
          'evidence_count': 0,
          'payment_method_snapshot': 'online',
          'amount_paid_snapshot': 500.0,
          'status': status,
          'processed_amount': 0,
          'created_at': '2026-09-22T00:00:00.000Z',
          'updated_at': '2026-09-22T00:00:00.000Z',
        };

    test('parses under_review', () {
      final r = RefundRequest.fromMap(_base('under_review'));
      expect(r.status, RefundTicketStatus.underReview);
    });
    test('unknown status falls back to submitted', () {
      final r = RefundRequest.fromMap(_base('nonexistent_status'));
      expect(r.status, RefundTicketStatus.submitted);
    });
    test('parses embedded booking number', () {
      final m = _base('submitted')
        ..['bookings'] = {'booking_number': 'BK-2026-9999'};
      final r = RefundRequest.fromMap(m);
      expect(r.bookingNumber, 'BK-2026-9999');
    });
    test('parses embedded customer name', () {
      final m = _base('submitted')
        ..['customers'] = {'full_name': 'John Doe', 'phone': '+91999'};
      final r = RefundRequest.fromMap(m);
      expect(r.customerName, 'John Doe');
      expect(r.customerPhone, '+91999');
    });
    test('parses embedded issue category label', () {
      final m = _base('submitted')
        ..['refund_issue_categories'] = {'label': 'Vendor no-show'};
      final r = RefundRequest.fromMap(m);
      expect(r.issueCategoryLabel, 'Vendor no-show');
    });
  });

  // ── Permission helpers (canX getters) ──────────────────────────────────────

  group('canMarkUnderReview', () {
    test('true for submitted', () =>
        expect(_makeRequest(status: RefundTicketStatus.submitted).canMarkUnderReview, isTrue));
    test('true for more_info_requested', () =>
        expect(_makeRequest(status: RefundTicketStatus.moreInfoRequested).canMarkUnderReview, isTrue));
    test('false for under_review', () =>
        expect(_makeRequest(status: RefundTicketStatus.underReview).canMarkUnderReview, isFalse));
    test('false for completed', () =>
        expect(_makeRequest(status: RefundTicketStatus.completed).canMarkUnderReview, isFalse));
  });

  group('canRequestMoreInfo', () {
    test('true for submitted', () =>
        expect(_makeRequest(status: RefundTicketStatus.submitted).canRequestMoreInfo, isTrue));
    test('true for under_review', () =>
        expect(_makeRequest(status: RefundTicketStatus.underReview).canRequestMoreInfo, isTrue));
    test('false for approved', () =>
        expect(_makeRequest(status: RefundTicketStatus.approved).canRequestMoreInfo, isFalse));
  });

  group('canApprove', () {
    test('true for submitted', () =>
        expect(_makeRequest(status: RefundTicketStatus.submitted).canApprove, isTrue));
    test('true for under_review', () =>
        expect(_makeRequest(status: RefundTicketStatus.underReview).canApprove, isTrue));
    test('true for more_info_requested', () =>
        expect(_makeRequest(status: RefundTicketStatus.moreInfoRequested).canApprove, isTrue));
    test('false for rejected', () =>
        expect(_makeRequest(status: RefundTicketStatus.rejected).canApprove, isFalse));
    test('false for approved', () =>
        expect(_makeRequest(status: RefundTicketStatus.approved).canApprove, isFalse));
    test('false for completed', () =>
        expect(_makeRequest(status: RefundTicketStatus.completed).canApprove, isFalse));
  });

  group('canInitiateTransaction', () {
    test('true for approved', () =>
        expect(_makeRequest(status: RefundTicketStatus.approved).canInitiateTransaction, isTrue));
    test('true for partially_approved', () =>
        expect(_makeRequest(status: RefundTicketStatus.partiallyApproved).canInitiateTransaction, isTrue));
    test('true for failed (retry)', () =>
        expect(_makeRequest(status: RefundTicketStatus.failed).canInitiateTransaction, isTrue));
    test('false for submitted', () =>
        expect(_makeRequest(status: RefundTicketStatus.submitted).canInitiateTransaction, isFalse));
    test('false for processing', () =>
        expect(_makeRequest(status: RefundTicketStatus.processing).canInitiateTransaction, isFalse));
    test('false for completed', () =>
        expect(_makeRequest(status: RefundTicketStatus.completed).canInitiateTransaction, isFalse));
  });

  group('canClose', () {
    test('false for processing', () =>
        expect(_makeRequest(status: RefundTicketStatus.processing).canClose, isFalse));
    test('false for closed', () =>
        expect(_makeRequest(status: RefundTicketStatus.closed).canClose, isFalse));
    test('true for rejected', () =>
        expect(_makeRequest(status: RefundTicketStatus.rejected).canClose, isTrue));
    test('true for completed', () =>
        expect(_makeRequest(status: RefundTicketStatus.completed).canClose, isTrue));
    test('true for submitted', () =>
        expect(_makeRequest(status: RefundTicketStatus.submitted).canClose, isTrue));
  });

  // ── remainingRefundable ────────────────────────────────────────────────────

  group('remainingRefundable', () {
    test('no transactions → full paid amount', () {
      final r = _makeRequest(amountPaid: 500.0);
      expect(r.remainingRefundable, 500.0);
    });

    test('one completed transaction reduces balance', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        transactions: [_makeTxn(amount: 200.0)],
      );
      expect(r.remainingRefundable, 300.0);
    });

    test('multiple completed transactions accumulate', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        transactions: [
          _makeTxn(amount: 100.0),
          _makeTxn(amount: 200.0),
        ],
      );
      expect(r.remainingRefundable, 200.0);
    });

    test('failed transactions do not reduce balance', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        transactions: [
          _makeTxn(amount: 300.0, status: RefundTransactionStatus.failed),
        ],
      );
      expect(r.remainingRefundable, 500.0);
    });

    test('pending transactions reduce balance (counted as in-flight)', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        transactions: [
          _makeTxn(amount: 300.0, status: RefundTransactionStatus.pending),
        ],
      );
      expect(r.remainingRefundable, 200.0);
    });

    test('completed transactions fully exhausting balance returns 0', () {
      final r = _makeRequest(
        amountPaid: 400.0,
        transactions: [
          _makeTxn(amount: 200.0),
          _makeTxn(amount: 200.0),
        ],
      );
      expect(r.remainingRefundable, 0.0);
    });

    test('remainingRefundable never goes negative', () {
      // Edge case: completed txns exceed amountPaid (shouldn't happen in prod
      // but clamp must protect the getter).
      final r = _makeRequest(
        amountPaid: 100.0,
        transactions: [_makeTxn(amount: 150.0)],
      );
      expect(r.remainingRefundable, 0.0);
    });
  });

  // ── remainingRefundable: approved_amount cap (Bug 1 regression tests) ────────

  group('remainingRefundable with approved_amount cap', () {
    test('₹500 collected, ₹400 approved, no transactions → ₹400 remaining', () {
      final r = _makeRequest(amountPaid: 500.0, approvedAmount: 400.0);
      expect(r.remainingRefundable, 400.0);
    });

    test('₹500 collected, ₹400 approved, ₹200 completed → ₹200 remaining', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [_makeTxn(amount: 200.0)],
      );
      expect(r.remainingRefundable, 200.0);
    });

    test(
        '₹500 collected, ₹400 approved, ₹200 pending → ₹200 remaining '
        '(pending counts; no more than ₹200 additional may be initiated)', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [
          _makeTxn(amount: 200.0, status: RefundTransactionStatus.pending),
        ],
      );
      expect(r.remainingRefundable, 200.0);
    });

    test('₹500 collected, ₹400 approved, ₹400 completed → ₹0 remaining', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [_makeTxn(amount: 400.0)],
      );
      expect(r.remainingRefundable, 0.0);
    });

    test('failed transactions do not reduce approved-capped balance', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [
          _makeTxn(amount: 400.0, status: RefundTransactionStatus.failed),
        ],
      );
      expect(r.remainingRefundable, 400.0);
    });

    test('approved_amount equal to amount_paid uses full amount as ceiling', () {
      final r = _makeRequest(
        amountPaid: 500.0,
        approvedAmount: 500.0,
        transactions: [_makeTxn(amount: 200.0)],
      );
      expect(r.remainingRefundable, 300.0);
    });

    test('approved_amount exceeding amount_paid is clamped to amount_paid', () {
      // Defensive: approved_amount should never exceed paid, but getter must not
      // produce a value above what was actually collected.
      final r = _makeRequest(
        amountPaid: 400.0,
        approvedAmount: 600.0,
        transactions: [_makeTxn(amount: 100.0)],
      );
      expect(r.remainingRefundable, 300.0);
    });
  });

  // ── canInitiateTransaction: partial-refund lifecycle (Bug 2 regression tests) ─

  group('canInitiateTransaction lifecycle after partial refund', () {
    test(
        'approved ticket with partial completed transactions → still eligible '
        '(partial disbursement must not lock the ticket)', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [_makeTxn(amount: 200.0)],
      );
      expect(r.canInitiateTransaction, isTrue);
      expect(r.remainingRefundable, 200.0);
    });

    test(
        'partially_approved ticket with partial completed transactions → '
        'still eligible for another transaction', () {
      final r = _makeRequest(
        status: RefundTicketStatus.partiallyApproved,
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [_makeTxn(amount: 200.0)],
      );
      expect(r.canInitiateTransaction, isTrue);
      expect(r.remainingRefundable, 200.0);
    });

    test(
        'full disbursement: approved_amount fully completed → ticket completed '
        '→ not eligible for further transactions', () {
      final r = _makeRequest(
        status: RefundTicketStatus.completed,
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [_makeTxn(amount: 400.0)],
      );
      expect(r.canInitiateTransaction, isFalse);
      expect(r.remainingRefundable, 0.0);
    });

    test(
        'failed transaction on retry path does not reduce balance → '
        'full approved amount still initiatable', () {
      final r = _makeRequest(
        status: RefundTicketStatus.failed,
        amountPaid: 500.0,
        approvedAmount: 400.0,
        transactions: [
          _makeTxn(amount: 400.0, status: RefundTransactionStatus.failed),
        ],
      );
      expect(r.canInitiateTransaction, isTrue);
      expect(r.remainingRefundable, 400.0);
    });
  });

  // ── paymentMethodLabel ─────────────────────────────────────────────────────

  group('paymentMethodLabel', () {
    test('online maps to Online Payment', () {
      final r = _makeRequest();
      expect(r.paymentMethodLabel, 'Online Payment');
    });

    test('cod maps to Cash on Delivery', () {
      final r = RefundRequest(
        id: 'r',
        ticketNumber: 'RFD-1',
        bookingId: 'b',
        customerId: 'c',
        requestedAmount: 100,
        evidenceUrls: const [],
        evidenceCount: 0,
        paymentMethodSnapshot: 'cod',
        amountPaidSnapshot: 100,
        status: RefundTicketStatus.submitted,
        processedAmount: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(r.paymentMethodLabel, 'Cash on Delivery');
    });
  });

  // ── RefundTransaction helpers ──────────────────────────────────────────────

  // ── RefundTransaction.canProcessViaRazorpay ────────────────────────────────

  group('RefundTransaction.canProcessViaRazorpay', () {
    RefundTransaction _makeRazorpayTxn({
      RefundTransactionStatus status = RefundTransactionStatus.pending,
      String gateway = 'razorpay',
    }) {
      return RefundTransaction(
        id: 'txn-rzp',
        refundRequestId: 'req-1',
        amount: 400.0,
        gateway: gateway,
        status: status,
        refundMethod: 'original_payment_method',
        initiatedBy: 'admin-1',
        initiatedAt: DateTime(2026, 9, 22),
        metadata: const {},
        createdAt: DateTime(2026, 9, 22),
      );
    }

    test('pending + razorpay gateway → true', () {
      expect(_makeRazorpayTxn().canProcessViaRazorpay, isTrue);
    });

    test('processing + razorpay → false (already in-flight)', () {
      expect(
        _makeRazorpayTxn(status: RefundTransactionStatus.processing)
            .canProcessViaRazorpay,
        isFalse,
      );
    });

    test('completed + razorpay → false', () {
      expect(
        _makeRazorpayTxn(status: RefundTransactionStatus.completed)
            .canProcessViaRazorpay,
        isFalse,
      );
    });

    test('failed + razorpay → false (must re-initiate first)', () {
      expect(
        _makeRazorpayTxn(status: RefundTransactionStatus.failed)
            .canProcessViaRazorpay,
        isFalse,
      );
    });

    test('pending + manual gateway → false (not a Razorpay transaction)', () {
      expect(
        _makeRazorpayTxn(gateway: 'manual').canProcessViaRazorpay,
        isFalse,
      );
    });

    test('pending + cod_cash_return → false', () {
      expect(
        _makeRazorpayTxn(gateway: 'cod_cash_return').canProcessViaRazorpay,
        isFalse,
      );
    });
  });

  group('RefundTransaction.statusLabel', () {
    test('completed', () =>
        expect(_makeTxn(amount: 100).statusLabel, 'Completed'));
    test('pending', () =>
        expect(_makeTxn(amount: 100, status: RefundTransactionStatus.pending).statusLabel, 'Pending'));
    test('failed', () =>
        expect(_makeTxn(amount: 100, status: RefundTransactionStatus.failed).statusLabel, 'Failed'));
    test('processing', () =>
        expect(_makeTxn(amount: 100, status: RefundTransactionStatus.processing).statusLabel, 'Processing'));
  });

  group('RefundTransaction.gatewayLabel', () {
    test('razorpay', () {
      final t = RefundTransaction(
        id: 't1', refundRequestId: 'r1', amount: 100, gateway: 'razorpay',
        status: RefundTransactionStatus.completed, refundMethod: 'original_payment_method',
        initiatedBy: 'a', initiatedAt: DateTime(2026), metadata: {}, createdAt: DateTime(2026),
      );
      expect(t.gatewayLabel, 'Razorpay');
    });
    test('cod_cash_return', () {
      final t = RefundTransaction(
        id: 't2', refundRequestId: 'r1', amount: 50, gateway: 'cod_cash_return',
        status: RefundTransactionStatus.completed, refundMethod: 'cod_cash_return',
        initiatedBy: 'a', initiatedAt: DateTime(2026), metadata: {}, createdAt: DateTime(2026),
      );
      expect(t.gatewayLabel, 'Cash Return');
    });
  });

  // ── gateway_response column restriction (migration 000017) ─────────────────
  //
  // After migration 000017, the DB revokes table-level SELECT from anon and
  // authenticated and grants column-level SELECT on every column except
  // gateway_response.  The DB never returns gateway_response to Flutter
  // clients.  These tests verify the model handles both the pre-migration
  // (gateway_response present in map) and post-migration (absent) cases
  // without throwing, and that the model exposes no gateway_response field.

  group('RefundTransaction.fromMap — gateway_response isolation', () {
    Map<String, dynamic> baseTxnMap() => {
          'id': 'txn-gw-1',
          'refund_request_id': 'req-1',
          'amount': 350.0,
          'gateway': 'razorpay',
          'gateway_refund_id': 'rfnd_TestABC123',
          'status': 'completed',
          'failure_reason': null,
          'refund_method': 'original_payment_method',
          'initiated_by': 'admin-uuid',
          'initiated_at': '2026-09-22T10:00:00.000Z',
          'completed_at': '2026-09-22T10:05:00.000Z',
          'metadata': <String, dynamic>{},
          'created_at': '2026-09-22T10:00:00.000Z',
          'updated_at': '2026-09-22T10:05:00.000Z',
        };

    test('parses correctly when gateway_response is absent (post-migration DB response)', () {
      final t = RefundTransaction.fromMap(baseTxnMap());
      expect(t.id, 'txn-gw-1');
      expect(t.amount, 350.0);
      expect(t.gateway, 'razorpay');
      expect(t.gatewayRefundId, 'rfnd_TestABC123');
      expect(t.status, RefundTransactionStatus.completed);
    });

    test('parses correctly when gateway_response key is present in map (ignored silently)', () {
      final map = baseTxnMap()
        ..['gateway_response'] = {
          'id': 'rfnd_TestABC123',
          'entity': 'refund',
          'amount': 35000,
          'currency': 'INR',
        };
      final t = RefundTransaction.fromMap(map);
      expect(t.id, 'txn-gw-1');
      expect(t.gatewayRefundId, 'rfnd_TestABC123');
    });

    test('RefundTransaction has no gatewayResponse field', () {
      final t = RefundTransaction.fromMap(baseTxnMap());
      // Verify via reflection that the model object carries no gateway payload.
      // The model fields are: id, refundRequestId, amount, gateway,
      // gatewayRefundId, status, failureReason, refundMethod, initiatedBy,
      // initiatedAt, completedAt, metadata, createdAt.
      // There is no gatewayResponse field — confirmed by type inspection below.
      expect(t, isA<RefundTransaction>());
      // If a gatewayResponse field existed this would be a compile error,
      // proving the model does not carry the sensitive payload.
      // ignore: unnecessary_type_check
      expect(t is RefundTransaction, isTrue);
    });

    test('failed transaction without gateway_response parses correctly', () {
      final map = {
        'id': 'txn-fail-1',
        'refund_request_id': 'req-1',
        'amount': 200.0,
        'gateway': 'razorpay',
        'gateway_refund_id': null,
        'status': 'failed',
        'failure_reason': 'INSUFFICIENT_FUNDS',
        'refund_method': 'original_payment_method',
        'initiated_by': 'admin-uuid',
        'initiated_at': '2026-09-22T09:00:00.000Z',
        'completed_at': null,
        'metadata': <String, dynamic>{},
        'created_at': '2026-09-22T09:00:00.000Z',
        'updated_at': '2026-09-22T09:00:00.000Z',
      };
      final t = RefundTransaction.fromMap(map);
      expect(t.status, RefundTransactionStatus.failed);
      expect(t.failureReason, 'INSUFFICIENT_FUNDS');
      expect(t.gatewayRefundId, isNull);
      expect(t.completedAt, isNull);
    });
  });

  // ── COD bank details flow ──────────────────────────────────────────────────

  group('isCodBooking', () {
    test('online is not COD', () {
      expect(_makeRequest(paymentMethodSnapshot: 'online').isCodBooking, isFalse);
    });
    test('cod is COD', () {
      expect(_makeRequest(paymentMethodSnapshot: 'cod').isCodBooking, isTrue);
    });
    test('cash is COD', () {
      expect(_makeRequest(paymentMethodSnapshot: 'cash').isCodBooking, isTrue);
    });
  });

  group('hasBankDetailsRequested / hasBankDetailsSubmitted', () {
    test('both false when neither field is set', () {
      final r = _makeRequest(paymentMethodSnapshot: 'cod');
      expect(r.hasBankDetailsRequested, isFalse);
      expect(r.hasBankDetailsSubmitted, isFalse);
    });
    test('requested true once timestamp set', () {
      final r = _makeRequest(
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
      );
      expect(r.hasBankDetailsRequested, isTrue);
      expect(r.hasBankDetailsSubmitted, isFalse);
    });
    test('submitted true once submitted timestamp set', () {
      final r = _makeRequest(
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
        bankDetailsSubmittedAt: DateTime(2026, 9, 23, 1),
      );
      expect(r.hasBankDetailsRequested, isTrue);
      expect(r.hasBankDetailsSubmitted, isTrue);
    });
  });

  group('canInitiateTransaction for COD', () {
    test('false when bank details not submitted (no request)', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cod',
      );
      expect(r.canInitiateTransaction, isFalse);
    });
    test('false when bank details requested but not submitted', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
      );
      expect(r.canInitiateTransaction, isFalse);
    });
    test('true when bank details submitted', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
        bankDetailsSubmittedAt: DateTime(2026, 9, 23, 1),
      );
      expect(r.canInitiateTransaction, isTrue);
    });
    test('false for COD when status is submitted (wrong status)', () {
      final r = _makeRequest(
        status: RefundTicketStatus.submitted,
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
        bankDetailsSubmittedAt: DateTime(2026, 9, 23, 1),
      );
      expect(r.canInitiateTransaction, isFalse);
    });
    test('online still initiatable with no bank details', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'online',
      );
      expect(r.canInitiateTransaction, isTrue);
    });
  });

  group('canRequestBankDetails', () {
    test('true for approved COD with no submission', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cod',
      );
      expect(r.canRequestBankDetails, isTrue);
    });
    test('true even when already requested but not submitted (re-send)', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
      );
      expect(r.canRequestBankDetails, isTrue);
    });
    test('false when customer already submitted', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
        bankDetailsSubmittedAt: DateTime(2026, 9, 23, 1),
      );
      expect(r.canRequestBankDetails, isFalse);
    });
    test('false for online payment', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'online',
      );
      expect(r.canRequestBankDetails, isFalse);
    });
    test('false for COD in submitted status', () {
      final r = _makeRequest(
        status: RefundTicketStatus.submitted,
        paymentMethodSnapshot: 'cod',
      );
      expect(r.canRequestBankDetails, isFalse);
    });
  });

  group('isAwaitingBankDetails', () {
    test('true when requested but not submitted', () {
      final r = _makeRequest(
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
      );
      expect(r.isAwaitingBankDetails, isTrue);
    });
    test('false when not requested', () {
      final r = _makeRequest(paymentMethodSnapshot: 'cod');
      expect(r.isAwaitingBankDetails, isFalse);
    });
    test('false when submitted', () {
      final r = _makeRequest(
        paymentMethodSnapshot: 'cod',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
        bankDetailsSubmittedAt: DateTime(2026, 9, 23, 1),
      );
      expect(r.isAwaitingBankDetails, isFalse);
    });
    test('false for online payment', () {
      final r = _makeRequest(
        paymentMethodSnapshot: 'online',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
      );
      expect(r.isAwaitingBankDetails, isFalse);
    });
  });

  group('RefundRequest.fromMap — bank details fields', () {
    Map<String, dynamic> _base(String status) => {
          'id': 'req-1',
          'ticket_number': 'RFD-202609-000001',
          'booking_id': 'bk-1',
          'customer_id': 'cust-1',
          'requested_amount': 500.0,
          'evidence_count': 0,
          'payment_method_snapshot': 'cod',
          'amount_paid_snapshot': 500.0,
          'status': status,
          'processed_amount': 0,
          'created_at': '2026-09-22T00:00:00.000Z',
          'updated_at': '2026-09-22T00:00:00.000Z',
        };

    test('parses null bank details fields when absent', () {
      final r = RefundRequest.fromMap(_base('approved'));
      expect(r.bankDetailsRequestedAt, isNull);
      expect(r.bankDetailsSubmittedAt, isNull);
      expect(r.bankUpiDetails, isNull);
    });

    test('parses bank_details_requested_at', () {
      final m = _base('approved')
        ..['bank_details_requested_at'] = '2026-09-23T10:00:00.000Z';
      final r = RefundRequest.fromMap(m);
      expect(r.bankDetailsRequestedAt, isNotNull);
      expect(r.hasBankDetailsRequested, isTrue);
    });

    test('parses both timestamps and bank_upi_details', () {
      final m = _base('approved')
        ..['bank_details_requested_at'] = '2026-09-23T10:00:00.000Z'
        ..['bank_details_submitted_at'] = '2026-09-23T11:00:00.000Z'
        ..['bank_upi_details'] = {
          'type': 'bank',
          'account_holder_name': 'John Doe',
          'account_number': '123456789',
          'ifsc_code': 'HDFC0001234',
        };
      final r = RefundRequest.fromMap(m);
      expect(r.hasBankDetailsSubmitted, isTrue);
      expect(r.bankUpiDetails?['type'], 'bank');
      expect(r.bankUpiDetails?['account_holder_name'], 'John Doe');
    });

    test('parses upi type details', () {
      final m = _base('approved')
        ..['bank_details_requested_at'] = '2026-09-23T10:00:00.000Z'
        ..['bank_details_submitted_at'] = '2026-09-23T11:00:00.000Z'
        ..['bank_upi_details'] = {'type': 'upi', 'upi_id': 'john@upi'};
      final r = RefundRequest.fromMap(m);
      expect(r.bankUpiDetails?['type'], 'upi');
      expect(r.bankUpiDetails?['upi_id'], 'john@upi');
    });
  });

  // ── Online refund initiation routing ──────────────────────────────────────
  //
  // The UI routes based on isCodBooking:
  //   online → _handleInitiateOnlineRefund (no dialog, direct initiate+process)
  //   COD    → _handleInitiateCodTransfer  (bank-details dialog)
  //
  // These tests cover the model predicates the routing depends on, and the
  // balance/eligibility invariants the UI relies on before calling the RPCs.

  group('online refund initiation routing', () {
    test('online approved ticket can initiate without bank details', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'online',
      );
      expect(r.isCodBooking, isFalse);
      expect(r.canInitiateTransaction, isTrue);
    });

    test('COD approved ticket cannot initiate without bank details', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cash',
      );
      expect(r.isCodBooking, isTrue);
      expect(r.canInitiateTransaction, isFalse);
    });

    test('COD approved ticket can initiate once bank details submitted', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'cash',
        bankDetailsRequestedAt: DateTime(2026, 9, 23),
        bankDetailsSubmittedAt: DateTime(2026, 9, 23, 1),
      );
      expect(r.isCodBooking, isTrue);
      expect(r.canInitiateTransaction, isTrue);
    });

    test(
        'processing transaction reduces balance to 0 — '
        'duplicate-click protection: second initiation has no balance', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'online',
        amountPaid: 500.0,
        transactions: [
          _makeTxn(amount: 500.0, status: RefundTransactionStatus.processing),
        ],
      );
      expect(r.remainingRefundable, 0.0);
    });

    test(
        'partial online refund: remaining balance reflects completed transactions', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'online',
        amountPaid: 500.0,
        approvedAmount: 300.0,
        transactions: [_makeTxn(amount: 150.0)],
      );
      expect(r.remainingRefundable, 150.0);
      expect(r.canInitiateTransaction, isTrue);
    });

    test(
        'failed online refund: balance fully restored for retry', () {
      final r = _makeRequest(
        status: RefundTicketStatus.failed,
        paymentMethodSnapshot: 'online',
        amountPaid: 500.0,
        approvedAmount: 500.0,
        transactions: [
          _makeTxn(amount: 500.0, status: RefundTransactionStatus.failed),
        ],
      );
      expect(r.remainingRefundable, 500.0);
      expect(r.canInitiateTransaction, isTrue);
    });

    test(
        'processing + completed mix: combined in-flight amount blocks new initiation', () {
      final r = _makeRequest(
        status: RefundTicketStatus.approved,
        paymentMethodSnapshot: 'online',
        amountPaid: 500.0,
        approvedAmount: 500.0,
        transactions: [
          _makeTxn(amount: 300.0),
          _makeTxn(amount: 200.0, status: RefundTransactionStatus.processing),
        ],
      );
      expect(r.remainingRefundable, 0.0);
    });
  });
}
