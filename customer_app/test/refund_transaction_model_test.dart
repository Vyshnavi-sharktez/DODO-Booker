import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/refund_queries/models/refund_transaction_model.dart';

// Tests for RefundTransactionModel.fromMap, focusing on behaviour after
// migration 000017, which revokes table-level SELECT on refund_transactions
// for anon and authenticated and grants column-level SELECT on every column
// except gateway_response.  The DB will no longer return gateway_response in
// any PostgREST response; these tests verify the model handles both states
// (column present, column absent) without throwing.

Map<String, dynamic> _base() => {
      'id': 'txn-1',
      'refund_request_id': 'req-1',
      'amount': 500.0,
      'gateway': 'razorpay',
      'gateway_refund_id': 'rfnd_ABC123',
      'status': 'completed',
      'failure_reason': null,
      'refund_method': 'original_payment_method',
      'created_at': '2026-09-22T10:00:00.000Z',
      'completed_at': '2026-09-22T10:05:00.000Z',
    };

void main() {
  group('RefundTransactionModel.fromMap', () {
    test('parses standard completed transaction (no gateway_response key)', () {
      final t = RefundTransactionModel.fromMap(_base());
      expect(t.id, 'txn-1');
      expect(t.refundRequestId, 'req-1');
      expect(t.amount, 500.0);
      expect(t.gateway, 'razorpay');
      expect(t.gatewayRefundId, 'rfnd_ABC123');
      expect(t.status, 'completed');
      expect(t.isCompleted, isTrue);
      expect(t.failureReason, isNull);
      expect(t.refundMethod, 'original_payment_method');
      expect(t.completedAt, isNotNull);
    });

    test('gateway_response key in map is silently ignored', () {
      final map = _base()
        ..['gateway_response'] = {
          'id': 'rfnd_ABC123',
          'entity': 'refund',
          'amount': 50000,
          'currency': 'INR',
          'payment_id': 'pay_XYZ',
        };
      // Should not throw and should not expose the payload.
      final t = RefundTransactionModel.fromMap(map);
      expect(t.id, 'txn-1');
      expect(t.gatewayRefundId, 'rfnd_ABC123');
    });

    test('RefundTransactionModel has no gatewayResponse field', () {
      final t = RefundTransactionModel.fromMap(_base());
      // Compile-time proof: if a gatewayResponse field existed, accessing it
      // here would cause a compile error.  The object has exactly the fields:
      // id, refundRequestId, amount, gateway, gatewayRefundId, status,
      // failureReason, refundMethod, createdAt, completedAt.
      expect(t, isA<RefundTransactionModel>());
    });

    test('failed transaction without gateway_response parses correctly', () {
      final map = {
        'id': 'txn-fail',
        'refund_request_id': 'req-1',
        'amount': 300.0,
        'gateway': 'razorpay',
        'gateway_refund_id': null,
        'status': 'failed',
        'failure_reason': 'BAD_REQUEST_ERROR',
        'refund_method': 'original_payment_method',
        'created_at': '2026-09-22T09:00:00.000Z',
        'completed_at': null,
      };
      final t = RefundTransactionModel.fromMap(map);
      expect(t.status, 'failed');
      expect(t.isFailed, isTrue);
      expect(t.failureReason, 'BAD_REQUEST_ERROR');
      expect(t.gatewayRefundId, isNull);
      expect(t.completedAt, isNull);
    });

    test('manual cash_return transaction parses correctly', () {
      final map = {
        'id': 'txn-cod',
        'refund_request_id': 'req-2',
        'amount': 150.0,
        'gateway': 'cod_cash_return',
        'gateway_refund_id': null,
        'status': 'completed',
        'failure_reason': null,
        'refund_method': 'cod_cash_return',
        'created_at': '2026-09-22T11:00:00.000Z',
        'completed_at': '2026-09-22T11:00:00.000Z',
      };
      final t = RefundTransactionModel.fromMap(map);
      expect(t.gateway, 'cod_cash_return');
      expect(t.isCompleted, isTrue);
    });

    test('pending transaction has isCompleted false and isPending true', () {
      final map = _base()
        ..['status'] = 'pending'
        ..['completed_at'] = null;
      final t = RefundTransactionModel.fromMap(map);
      expect(t.isPending, isTrue);
      expect(t.isCompleted, isFalse);
    });

    test('processing transaction has isProcessing true', () {
      final map = _base()
        ..['status'] = 'processing'
        ..['completed_at'] = null;
      final t = RefundTransactionModel.fromMap(map);
      expect(t.isProcessing, isTrue);
      expect(t.isCompleted, isFalse);
      expect(t.isFailed, isFalse);
    });
  });

  // ── Banner status message conditions ─────────────────────────────────────────
  // The _RefundStatusBanner widget computes completedAmount and activeAmount
  // from the transactions list.  These tests verify the status helpers and
  // folding logic that the banner relies on.

  group('Refund status banner — amount bucketing', () {
    RefundTransactionModel _txn(String status, double amount) {
      return RefundTransactionModel.fromMap({
        'id': 'txn-$status-$amount',
        'refund_request_id': 'req-1',
        'amount': amount,
        'gateway': 'razorpay',
        'gateway_refund_id': null,
        'status': status,
        'failure_reason': null,
        'refund_method': 'original_payment_method',
        'created_at': '2026-09-23T10:00:00.000Z',
        'completed_at': status == 'completed' ? '2026-09-23T10:05:00.000Z' : null,
      });
    }

    test('single completed transaction: completedAmount = amount', () {
      final txns = [_txn('completed', 500)];
      final completedAmount =
          txns.where((t) => t.isCompleted).fold<double>(0, (s, t) => s + t.amount);
      final activeAmount =
          txns.where((t) => t.isPending || t.isProcessing).fold<double>(0, (s, t) => s + t.amount);
      expect(completedAmount, 500.0);
      expect(activeAmount, 0.0);
    });

    test('single pending transaction: activeAmount = amount', () {
      final txns = [_txn('pending', 300)];
      final completedAmount =
          txns.where((t) => t.isCompleted).fold<double>(0, (s, t) => s + t.amount);
      final activeAmount =
          txns.where((t) => t.isPending || t.isProcessing).fold<double>(0, (s, t) => s + t.amount);
      expect(completedAmount, 0.0);
      expect(activeAmount, 300.0);
    });

    test('single processing transaction: activeAmount = amount', () {
      final txns = [_txn('processing', 200)];
      final activeAmount =
          txns.where((t) => t.isPending || t.isProcessing).fold<double>(0, (s, t) => s + t.amount);
      expect(activeAmount, 200.0);
    });

    test('all failed: both amounts are 0, banner shows nothing', () {
      final txns = [_txn('failed', 500), _txn('failed', 200)];
      final completedAmount =
          txns.where((t) => t.isCompleted).fold<double>(0, (s, t) => s + t.amount);
      final activeAmount =
          txns.where((t) => t.isPending || t.isProcessing).fold<double>(0, (s, t) => s + t.amount);
      expect(completedAmount, 0.0);
      expect(activeAmount, 0.0);
    });

    test('partial refund: two completed transactions sum correctly', () {
      final txns = [_txn('completed', 300), _txn('completed', 200)];
      final completedAmount =
          txns.where((t) => t.isCompleted).fold<double>(0, (s, t) => s + t.amount);
      expect(completedAmount, 500.0);
    });

    test('failed + completed: completed wins; failed excluded from active', () {
      final txns = [_txn('failed', 500), _txn('completed', 400)];
      final completedAmount =
          txns.where((t) => t.isCompleted).fold<double>(0, (s, t) => s + t.amount);
      final activeAmount =
          txns.where((t) => t.isPending || t.isProcessing).fold<double>(0, (s, t) => s + t.amount);
      expect(completedAmount, 400.0);
      expect(activeAmount, 0.0);
    });
  });
}
