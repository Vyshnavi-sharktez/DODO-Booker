import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_image.dart';

class BookingImagesDatasource {
  const BookingImagesDatasource(this._client);
  final SupabaseClient _client;

  static const _bucket = 'booking-photos';

  /// Uploads [bytes] to Storage and inserts a row in booking_images.
  /// Returns the public URL of the uploaded image.
  Future<String> uploadAndSave({
    required String bookingId,
    required String imageType,
    required Uint8List bytes,
    required String contentType,
    String? uploadedBy,
  }) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '$bookingId/$imageType/$fileName';

    // ── TEMP LOGGING ──────────────────────────────────────────────────────────
    debugPrint('[PHOTOS][1] about to call uploadBinary — bucket=$_bucket path=$path bytes=${bytes.lengthInBytes}');
    try {
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      debugPrint('[PHOTOS][2] uploadBinary succeeded');
    } catch (e, st) {
      debugPrint('[PHOTOS][ERROR] uploadBinary FAILED');
      debugPrint('[PHOTOS][ERROR] exception : $e');
      debugPrint('[PHOTOS][ERROR] stackTrace:\n$st');
      rethrow;
    }
    // ── END TEMP LOGGING ──────────────────────────────────────────────────────

    final url = _client.storage.from(_bucket).getPublicUrl(path);

    // ── TEMP LOGGING ──────────────────────────────────────────────────────────
    debugPrint('[PHOTOS][3] about to insert into booking_images — booking_id=$bookingId image_type=$imageType url=$url');
    try {
      await _client.from('booking_images').insert({
        'booking_id': bookingId,
        'image_type': imageType,
        'image_url': url,
        // ignore: use_null_aware_elements
        if (uploadedBy != null) 'uploaded_by': uploadedBy,
      });
      debugPrint('[PHOTOS][4] booking_images insert succeeded');
    } catch (e, st) {
      debugPrint('[PHOTOS][ERROR] booking_images insert FAILED');
      debugPrint('[PHOTOS][ERROR] exception : $e');
      debugPrint('[PHOTOS][ERROR] stackTrace:\n$st');
      rethrow;
    }
    // ── END TEMP LOGGING ──────────────────────────────────────────────────────

    return url;
  }

  Future<List<BookingImage>> fetchImages(String bookingId) async {
    final rows = await _client
        .from('booking_images')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at');
    return (rows as List)
        .map((r) => BookingImage.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
