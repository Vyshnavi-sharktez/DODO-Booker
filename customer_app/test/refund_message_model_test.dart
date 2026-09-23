import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/refund_queries/models/refund_message_model.dart';

// Tests for RefundMessageModel.fromMap including the new attachment_urls field
// added in migration 20260922000018.

Map<String, dynamic> _base({
  String senderType = 'admin',
  bool isInternal = false,
  String? attachmentUrl,
  Object? attachmentUrls = const <String>[],
}) =>
    {
      'id': 'msg-1',
      'refund_request_id': 'req-1',
      'sender_type': senderType,
      'sender_id': 'user-1',
      'message': 'Test message',
      'attachment_url': attachmentUrl,
      'attachment_urls': attachmentUrls,
      'is_internal': isInternal,
      'created_at': '2026-09-22T10:00:00.000Z',
    };

void main() {
  group('RefundMessageModel.fromMap', () {
    test('parses admin message', () {
      final m = RefundMessageModel.fromMap(_base());
      expect(m.id, 'msg-1');
      expect(m.senderType, 'admin');
      expect(m.isFromAdmin, isTrue);
      expect(m.isFromCustomer, isFalse);
      expect(m.message, 'Test message');
      expect(m.attachmentUrls, isEmpty);
      expect(m.isInternal, isFalse);
    });

    test('parses customer message', () {
      final m = RefundMessageModel.fromMap(_base(senderType: 'customer'));
      expect(m.isFromCustomer, isTrue);
      expect(m.isFromAdmin, isFalse);
    });

    test('parses attachment_urls list', () {
      final m = RefundMessageModel.fromMap(_base(
        attachmentUrls: ['req-1/cust_abc/1693.jpg', 'req-1/cust_abc/1694.png'],
      ));
      expect(m.attachmentUrls, hasLength(2));
      expect(m.attachmentUrls[0], contains('1693.jpg'));
    });

    test('missing attachment_urls key returns empty list', () {
      final map = _base()..remove('attachment_urls');
      final m = RefundMessageModel.fromMap(map);
      expect(m.attachmentUrls, isEmpty);
    });

    test('null attachment_urls returns empty list', () {
      final m = RefundMessageModel.fromMap(_base(attachmentUrls: null));
      expect(m.attachmentUrls, isEmpty);
    });

    test('parses legacy attachment_url', () {
      final m = RefundMessageModel.fromMap(
          _base(attachmentUrl: 'https://storage.example.com/old.jpg'));
      expect(m.attachmentUrl, 'https://storage.example.com/old.jpg');
    });

    test('null sender_type falls back to admin', () {
      final map = _base()..['sender_type'] = null;
      final m = RefundMessageModel.fromMap(map);
      expect(m.senderType, 'admin');
    });

    test('created_at parses as DateTime', () {
      final m = RefundMessageModel.fromMap(_base());
      expect(m.createdAt, isA<DateTime>());
      expect(m.createdAt.year, 2026);
    });
  });

  // ── allAttachmentPaths ─────────────────────────────────────────────────────

  group('RefundMessageModel.allAttachmentPaths', () {
    test('returns attachment_urls when legacy is absent', () {
      final m = RefundMessageModel.fromMap(_base(
        attachmentUrls: ['path/a.jpg', 'path/b.jpg'],
      ));
      expect(m.allAttachmentPaths, ['path/a.jpg', 'path/b.jpg']);
    });

    test('prepends legacy attachment_url if not in array', () {
      final m = RefundMessageModel.fromMap(_base(
        attachmentUrl: 'https://legacy.example.com/img.jpg',
        attachmentUrls: ['path/a.jpg'],
      ));
      expect(m.allAttachmentPaths.first,
          'https://legacy.example.com/img.jpg');
      expect(m.allAttachmentPaths.length, 2);
    });

    test('does not duplicate legacy URL already in array', () {
      const path = 'req-1/cust_abc/img.jpg';
      final m = RefundMessageModel.fromMap(_base(
        attachmentUrl: path,
        attachmentUrls: [path],
      ));
      expect(m.allAttachmentPaths.where((p) => p == path), hasLength(1));
    });

    test('empty when both are absent/empty', () {
      final m = RefundMessageModel.fromMap(_base());
      expect(m.allAttachmentPaths, isEmpty);
    });
  });

  // ── URL scheme safety (mirrors _MessageText._isSafeUrl) ───────────────────

  group('URL scheme safety', () {
    bool isSafe(String url) {
      try {
        final uri = Uri.parse(url);
        return uri.scheme == 'http' || uri.scheme == 'https';
      } catch (_) {
        return false;
      }
    }

    test('https is safe', () => expect(isSafe('https://dodo.app'), isTrue));
    test('http is safe', () => expect(isSafe('http://dodo.app'), isTrue));
    test('javascript: is rejected',
        () => expect(isSafe('javascript:void(0)'), isFalse));
    test('data: is rejected',
        () => expect(isSafe('data:text/html,test'), isFalse));
    test('file: is rejected',
        () => expect(isSafe('file:///etc/passwd'), isFalse));
    test('plain text is rejected',
        () => expect(isSafe('not a url'), isFalse));
    test('empty string is rejected', () => expect(isSafe(''), isFalse));
    test('ftp: is rejected',
        () => expect(isSafe('ftp://ftp.example.com'), isFalse));
  });
}
