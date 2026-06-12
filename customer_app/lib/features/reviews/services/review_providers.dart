import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'review_service.dart';
import '../models/review_model.dart';

final reviewServiceProvider = Provider<ReviewService>(
  (ref) => ReviewService(),
);

/// Checks if a review exists for a given booking ID.
final bookingReviewProvider =
    FutureProvider.family<ReviewModel?, String>((ref, bookingId) {
  return ref.read(reviewServiceProvider).getReviewForBooking(bookingId);
});

/// Fetches all reviews for a given service ID.
final reviewsForServiceProvider =
    FutureProvider.family<List<ReviewModel>, String>((ref, serviceId) {
  return ref.read(reviewServiceProvider).fetchReviewsForService(serviceId);
});
