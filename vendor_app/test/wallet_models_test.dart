import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/wallet/domain/models/wallet.dart';
import 'package:vendor_app/features/wallet/domain/models/transaction.dart';

void main() {
  group('TransactionType.fromString', () {
    test('top_up maps to topUp', () {
      expect(TransactionType.fromString('top_up'), TransactionType.topUp);
    });

    test('credit (legacy alias) maps to topUp', () {
      expect(TransactionType.fromString('credit'), TransactionType.topUp);
    });

    test('commission maps to commission', () {
      expect(TransactionType.fromString('commission'), TransactionType.commission);
    });

    test('debit (legacy alias) maps to commission', () {
      expect(TransactionType.fromString('debit'), TransactionType.commission);
    });

    test('penalty maps to penalty', () {
      expect(TransactionType.fromString('penalty'), TransactionType.penalty);
    });

    test('withdrawal (legacy alias) maps to penalty', () {
      expect(TransactionType.fromString('withdrawal'), TransactionType.penalty);
    });

    test('adjustment maps to adjustment', () {
      expect(TransactionType.fromString('adjustment'), TransactionType.adjustment);
    });

    test('settlement (legacy alias) maps to adjustment', () {
      expect(TransactionType.fromString('settlement'), TransactionType.adjustment);
    });

    test('null defaults to topUp', () {
      expect(TransactionType.fromString(null), TransactionType.topUp);
    });

    test('unknown string defaults to topUp', () {
      expect(TransactionType.fromString('gibberish'), TransactionType.topUp);
    });

    test('empty string defaults to topUp', () {
      expect(TransactionType.fromString(''), TransactionType.topUp);
    });
  });

  group('TransactionType.toDbValue', () {
    test('topUp → top_up', () {
      expect(TransactionType.topUp.toDbValue(), 'top_up');
    });

    test('commission → commission', () {
      expect(TransactionType.commission.toDbValue(), 'commission');
    });

    test('penalty → penalty', () {
      expect(TransactionType.penalty.toDbValue(), 'penalty');
    });

    test('adjustment → adjustment', () {
      expect(TransactionType.adjustment.toDbValue(), 'adjustment');
    });

    test('round-trip: fromString then toDbValue preserves canonical form', () {
      expect(TransactionType.fromString('credit').toDbValue(), 'top_up');
      expect(TransactionType.fromString('debit').toDbValue(), 'commission');
      expect(TransactionType.fromString('withdrawal').toDbValue(), 'penalty');
      expect(TransactionType.fromString('settlement').toDbValue(), 'adjustment');
    });
  });

  group('Wallet.fromMap', () {
    test('reads available_balance field', () {
      final w = Wallet.fromMap({
        'id': 'w1',
        'vendor_id': 'v1',
        'available_balance': 1500.0,
        'total_earnings': 5000.0,
        'total_withdrawn': 200.0,
      });
      expect(w.balance, 1500.0);
      expect(w.totalEarned, 5000.0);
      expect(w.totalWithdrawn, 200.0);
    });

    test('falls back to balance field when available_balance absent', () {
      final w = Wallet.fromMap({
        'id': 'w1',
        'vendor_id': 'v1',
        'balance': 750.0,
      });
      expect(w.balance, 750.0);
    });

    test('falls back to total_earned when total_earnings absent', () {
      final w = Wallet.fromMap({
        'id': 'w1',
        'vendor_id': 'v1',
        'total_earned': 3000.0,
      });
      expect(w.totalEarned, 3000.0);
    });

    test('missing balance defaults to 0.0', () {
      final w = Wallet.fromMap({'id': 'w1', 'vendor_id': 'v1'});
      expect(w.balance, 0.0);
      expect(w.totalEarned, 0.0);
      expect(w.totalWithdrawn, 0.0);
    });

    test('parses updated_at as DateTime', () {
      final ts = '2024-03-15T10:30:00.000Z';
      final w = Wallet.fromMap({'id': 'w1', 'vendor_id': 'v1', 'updated_at': ts});
      expect(w.updatedAt, DateTime.tryParse(ts));
    });

    test('updated_at null when absent', () {
      final w = Wallet.fromMap({'id': 'w1', 'vendor_id': 'v1'});
      expect(w.updatedAt, isNull);
    });

    test('vendorId stored on model', () {
      final w = Wallet.fromMap({'id': 'w1', 'vendor_id': 'vendor-abc'});
      expect(w.vendorId, 'vendor-abc');
    });
  });

  group('WalletTransaction.fromMap', () {
    test('parses full record correctly', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx1',
        'vendor_id': 'v1',
        'type': 'commission',
        'amount': 250.0,
        'balance_after': 1250.0,
        'reference_id': 'bk-99',
        'reference_type': 'booking',
        'description': 'Service fee',
        'created_by': 'system',
        'created_at': '2024-06-01T09:00:00Z',
      });
      expect(tx.id, 'tx1');
      expect(tx.type, TransactionType.commission);
      expect(tx.amount, 250.0);
      expect(tx.balanceAfter, 1250.0);
      expect(tx.referenceId, 'bk-99');
      expect(tx.referenceType, 'booking');
      expect(tx.description, 'Service fee');
      expect(tx.createdAt, isNotNull);
    });

    test('bookingId getter returns referenceId when referenceType is booking', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx2',
        'vendor_id': 'v1',
        'type': 'commission',
        'amount': 100.0,
        'reference_id': 'bk-123',
        'reference_type': 'booking',
      });
      expect(tx.bookingId, 'bk-123');
    });

    test('bookingId getter returns null when referenceType is not booking', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx3',
        'vendor_id': 'v1',
        'type': 'top_up',
        'amount': 500.0,
        'reference_type': 'payment',
      });
      expect(tx.bookingId, isNull);
    });

    test('backward-compat: legacy booking_id field populates referenceId', () {
      // Old DB rows used booking_id instead of reference_id + reference_type
      final tx = WalletTransaction.fromMap({
        'id': 'tx4',
        'vendor_id': 'v1',
        'type': 'commission',
        'amount': 75.0,
        'booking_id': 'bk-legacy',
      });
      expect(tx.referenceId, 'bk-legacy');
      expect(tx.referenceType, 'booking');
      expect(tx.bookingId, 'bk-legacy');
    });

    test('unknown type defaults to topUp', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx5',
        'vendor_id': 'v1',
        'type': 'unknown_future_type',
        'amount': 0.0,
      });
      expect(tx.type, TransactionType.topUp);
    });

    test('null type defaults to topUp', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx6',
        'vendor_id': 'v1',
        'type': null,
        'amount': 100.0,
      });
      expect(tx.type, TransactionType.topUp);
    });

    test('balanceAfter defaults to 0.0 when absent', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx7',
        'vendor_id': 'v1',
        'type': 'top_up',
        'amount': 200.0,
      });
      expect(tx.balanceAfter, 0.0);
    });

    test('amount parsed from int in map', () {
      final tx = WalletTransaction.fromMap({
        'id': 'tx8',
        'vendor_id': 'v1',
        'type': 'top_up',
        'amount': 500, // int, not double
      });
      expect(tx.amount, 500.0);
    });
  });
}
