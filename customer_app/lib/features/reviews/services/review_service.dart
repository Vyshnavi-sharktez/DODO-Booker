import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/review_model.dart';

class ReviewService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  Future<String> _getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    return row['id'] as String;
  }

  /// Returns the review for a booking, or null if none exists.
  Future<ReviewModel?> getReviewForBooking(String bookingId) async {
    debugPrint('[DODO][Review] Review loaded for bookingId=$bookingId');
    final data = await _client
        .from('customer_reviews')
        .select('*')
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (data == null) return null;
    return ReviewModel.fromJson(data);
  }

  /// Returns all reviews for a service (two-step via booking_items join).
  Future<List<ReviewModel>> fetchReviewsForService(String serviceId) async {
    // Step 1 — get booking_ids associated with this service
    final items = await _client
        .from('booking_items')
        .select('booking_id')
        .eq('service_id', serviceId);

    final bookingIds = (items as List)
        .map((e) => e['booking_id'] as String)
        .toList();

    if (bookingIds.isEmpty) return [];

    // Step 2 — fetch reviews for those bookings
    final data = await _client
        .from('customer_reviews')
        .select('*')
        .inFilter('booking_id', bookingIds)
        .order('created_at', ascending: false);

    final reviews = (data as List)
        .map((e) => ReviewModel.fromJson(e as Map<String, dynamic>))
        .toList();

    debugPrint('[DODO][Review] Review loaded: ${reviews.length} reviews for service $serviceId');
    return reviews;
  }

  /// Inserts a review and updates the service's denormalised rating.
  Future<void> submitReview({
    required String bookingId,
    required int rating,
    required String reviewText,
  }) async {
    final customerId = await _getCustomerId();

    // Duplicate guard
    final existing = await _client
        .from('customer_reviews')
        .select('id')
        .eq('booking_id', bookingId)
        .eq('customer_id', customerId)
        .maybeSingle();

    if (existing != null) {
      debugPrint('[DODO][Review] Duplicate review prevented for bookingId=$bookingId');
      throw Exception('You have already reviewed this booking.');
    }

    // Resolve vendor_id from bookings table
    final bookingRow = await _client
        .from('bookings')
        .select('vendor_id')
        .eq('id', bookingId)
        .maybeSingle();
    final vendorId = bookingRow?['vendor_id'] as String?;

    await _client.from('customer_reviews').insert({
      'booking_id': bookingId,
      'customer_id': customerId,
      'vendor_id': vendorId,
      'rating': rating,
      'review_text': reviewText.trim(),
    });

    debugPrint('[DODO][Review] Review submitted for bookingId=$bookingId rating=$rating');

    // Update denormalised rating on the services table
    final serviceId = await _getServiceIdForBooking(bookingId);
    if (serviceId != null) {
      await _updateServiceRating(serviceId, rating);
    }
  }

  Future<String?> _getServiceIdForBooking(String bookingId) async {
    final data = await _client
        .from('booking_items')
        .select('service_id')
        .eq('booking_id', bookingId)
        .maybeSingle();
    return data?['service_id'] as String?;
  }

  Future<void> _updateServiceRating(String serviceId, int newRating) async {
    final row = await _client
        .from('services')
        .select('rating, review_count')
        .eq('id', serviceId)
        .maybeSingle();

    if (row == null) return;

    final currentRating = (row['rating'] as num?)?.toDouble() ?? 0.0;
    final currentCount = (row['review_count'] as int?) ?? 0;
    final newCount = currentCount + 1;
    final updatedRating =
        ((currentRating * currentCount) + newRating) / newCount;

    await _client.from('services').update({
      'rating': double.parse(updatedRating.toStringAsFixed(2)),
      'review_count': newCount,
    }).eq('id', serviceId);
  }
}
