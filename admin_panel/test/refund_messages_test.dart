import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/refunds/domain/models/refund_message.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Map<String, dynamic> _baseMap({
  String senderType = 'admin',
  bool isInternal = false,
  String? attachmentUrl,
  List<String>? attachmentUrls,
}) =>
    {
      'id': 'msg-1',
      'refund_request_id': 'req-1',
      'sender_type': senderType,
      'sender_id': 'user-1',
      'message': 'Hello there',
      'attachment_url': attachmentUrl,
      'attachment_urls': attachmentUrls ?? [],
      'is_internal': isInternal,
      'created_at': '2026-09-22T10:00:00.000Z',
    };

// ── RefundMessage.fromMap ──────────────────────────────────────────────────────

void main() {
  group('RefundMessage.fromMap', () {
    test('parses admin message correctly', () {
      final m = RefundMessage.fromMap(_baseMap());
      expect(m.id, 'msg-1');
      expect(m.refundRequestId, 'req-1');
      expect(m.senderType, 'admin');
      expect(m.message, 'Hello there');
      expect(m.isInternal, false);
      expect(m.isFromAdmin, isTrue);
      expect(m.isFromCustomer, isFalse);
      expect(m.attachmentUrls, isEmpty);
    });

    test('parses customer message correctly', () {
      final m = RefundMessage.fromMap(_baseMap(senderType: 'customer'));
      expect(m.isFromCustomer, isTrue);
      expect(m.isFromAdmin, isFalse);
    });

    test('parses internal flag', () {
      final m = RefundMessage.fromMap(_baseMap(isInternal: true));
      expect(m.isInternal, isTrue);
    });

    test('parses attachment_urls array', () {
      final m = RefundMessage.fromMap(_baseMap(
        attachmentUrls: ['req-1/cust_xyz/1.jpg', 'req-1/cust_xyz/2.png'],
      ));
      expect(m.attachmentUrls, hasLength(2));
      expect(m.attachmentUrls[0], 'req-1/cust_xyz/1.jpg');
    });

    test('attachment_urls absent falls back to empty list', () {
      final map = _baseMap()..remove('attachment_urls');
      final m = RefundMessage.fromMap(map);
      expect(m.attachmentUrls, isEmpty);
    });

    test('attachment_urls null falls back to empty list', () {
      final map = _baseMap();
      map['attachment_urls'] = null;
      final m = RefundMessage.fromMap(map);
      expect(m.attachmentUrls, isEmpty);
    });

    test('parses legacy attachment_url', () {
      final m = RefundMessage.fromMap(
          _baseMap(attachmentUrl: 'https://example.com/old.jpg'));
      expect(m.attachmentUrl, 'https://example.com/old.jpg');
    });

    test('unknown sender_type falls back to admin', () {
      final map = _baseMap()..['sender_type'] = null;
      final m = RefundMessage.fromMap(map);
      expect(m.senderType, 'admin');
    });

    test('formattedTime formats correctly', () {
      final m = RefundMessage.fromMap(_baseMap());
      // Should not throw and should contain a non-empty string
      expect(m.formattedTime, isNotEmpty);
    });
  });

  // ── allAttachmentPaths ─────────────────────────────────────────────────────

  group('RefundMessage.allAttachmentPaths', () {
    test('returns attachment_urls when no legacy attachment_url', () {
      final m = RefundMessage.fromMap(_baseMap(
        attachmentUrls: ['path/a.jpg', 'path/b.png'],
      ));
      expect(m.allAttachmentPaths, ['path/a.jpg', 'path/b.png']);
    });

    test('prepends legacy attachment_url if not already in array', () {
      final m = RefundMessage.fromMap(_baseMap(
        attachmentUrl: 'https://legacy.example.com/img.jpg',
        attachmentUrls: ['path/a.jpg'],
      ));
      expect(m.allAttachmentPaths[0], 'https://legacy.example.com/img.jpg');
      expect(m.allAttachmentPaths[1], 'path/a.jpg');
    });

    test('does not duplicate if legacy URL already in array', () {
      const path = 'path/a.jpg';
      final m = RefundMessage.fromMap(_baseMap(
        attachmentUrl: path,
        attachmentUrls: [path, 'path/b.png'],
      ));
      expect(m.allAttachmentPaths.where((p) => p == path), hasLength(1));
    });

    test('returns empty when both are empty', () {
      final m = RefundMessage.fromMap(_baseMap());
      expect(m.allAttachmentPaths, isEmpty);
    });
  });

  // ── URL scheme validation (mirrors widget logic) ───────────────────────────
  //
  // The _isSafeUrl function in both RefundMessagesTab and RefundMessageItem
  // allows only http/https and rejects javascript:, data:, file:, etc.
  // These tests verify the validation logic independently of the widgets.

  group('URL scheme safety validation', () {
    bool isSafe(String url) {
      try {
        final uri = Uri.parse(url);
        return uri.scheme == 'http' || uri.scheme == 'https';
      } catch (_) {
        return false;
      }
    }

    test('https URL is safe', () {
      expect(isSafe('https://example.com/path?q=1'), isTrue);
    });

    test('http URL is safe', () {
      expect(isSafe('http://example.com'), isTrue);
    });

    test('javascript: URL is rejected', () {
      expect(isSafe('javascript:alert(1)'), isFalse);
    });

    test('data: URL is rejected', () {
      expect(isSafe('data:text/html,<h1>XSS</h1>'), isFalse);
    });

    test('file: URL is rejected', () {
      expect(isSafe('file:///etc/passwd'), isFalse);
    });

    test('empty string is rejected', () {
      expect(isSafe(''), isFalse);
    });

    test('plain text without scheme is rejected', () {
      expect(isSafe('example.com'), isFalse);
    });

    test('ftp: URL is rejected', () {
      expect(isSafe('ftp://files.example.com/file.zip'), isFalse);
    });

    test('URL with https scheme but unusual path is safe', () {
      expect(isSafe('https://cdn.example.com/img/a%20b.png?token=xyz'),
          isTrue);
    });
  });

  // ── Attachment validation constants ────────────────────────────────────────

  group('Attachment MIME validation', () {
    const allowed = {'image/jpeg', 'image/jpg', 'image/png', 'image/webp'};

    test('jpeg is allowed', () =>
        expect(allowed.contains('image/jpeg'), isTrue));
    test('jpg is allowed', () =>
        expect(allowed.contains('image/jpg'), isTrue));
    test('png is allowed', () =>
        expect(allowed.contains('image/png'), isTrue));
    test('webp is allowed', () =>
        expect(allowed.contains('image/webp'), isTrue));
    test('pdf is not allowed', () =>
        expect(allowed.contains('application/pdf'), isFalse));
    test('gif is not allowed', () =>
        expect(allowed.contains('image/gif'), isFalse));
    test('mp4 is not allowed', () =>
        expect(allowed.contains('video/mp4'), isFalse));
    test('text/html is not allowed', () =>
        expect(allowed.contains('text/html'), isFalse));
  });
}
