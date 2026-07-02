import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/datasources/bookings_remote_datasource.dart';
import '../../data/repositories/bookings_repository_impl.dart';
import '../../domain/models/booking.dart';
import '../../domain/repositories/i_bookings_repository.dart';
import '../../domain/usecases/get_vendor_bookings_usecase.dart';
import '../../domain/usecases/get_dodo_team_bookings_usecase.dart';
import '../../domain/usecases/initiate_completion_usecase.dart';
import '../../domain/usecases/reject_booking_usecase.dart';
import '../../domain/usecases/update_booking_status_usecase.dart';
import '../../domain/usecases/verify_completion_otp_usecase.dart';

// ── DI chain ─────────────────────────────────────────────────────────────────

final bookingsDatasourceProvider = Provider<BookingsRemoteDatasource>(
  (ref) => BookingsRemoteDatasource(ref.watch(supabaseClientProvider)),
);

final bookingsRepositoryProvider = Provider<IBookingsRepository>(
  (ref) => BookingsRepositoryImpl(ref.watch(bookingsDatasourceProvider)),
);

final getVendorBookingsUseCaseProvider = Provider<GetVendorBookingsUseCase>(
  (ref) => GetVendorBookingsUseCase(ref.watch(bookingsRepositoryProvider)),
);

final getDodoTeamBookingsUseCaseProvider = Provider<GetDodoTeamBookingsUseCase>(
  (ref) => GetDodoTeamBookingsUseCase(ref.watch(bookingsRepositoryProvider)),
);

final updateBookingStatusUseCaseProvider = Provider<UpdateBookingStatusUseCase>(
  (ref) => UpdateBookingStatusUseCase(ref.watch(bookingsRepositoryProvider)),
);

final rejectBookingUseCaseProvider = Provider<RejectBookingUseCase>(
  (ref) => RejectBookingUseCase(ref.watch(bookingsRepositoryProvider)),
);

final initiateCompletionUseCaseProvider = Provider<InitiateCompletionUseCase>(
  (ref) => InitiateCompletionUseCase(ref.watch(bookingsRepositoryProvider)),
);

final verifyCompletionOtpUseCaseProvider = Provider<VerifyCompletionOtpUseCase>(
  (ref) => VerifyCompletionOtpUseCase(ref.watch(bookingsRepositoryProvider)),
);

// ── Live bookings (Supabase) ──────────────────────────────────────────────────
// For DODO Team members, bookings are fetched by dodo_team_id.
// For external vendors, bookings are fetched by vendor_id (includes rejected,
// because vendor_id is preserved on rejection).

final vendorBookingsProvider =
    FutureProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentVendorUserProvider);
  if (user == null) return Future.value([]);
  if (user.isDodoTeam && user.dodoTeamId != null) {
    return ref.read(getDodoTeamBookingsUseCaseProvider).call(user.dodoTeamId!);
  }
  return ref.read(getVendorBookingsUseCaseProvider).call(user.id);
});

/// Fetches a single booking by ID — used for deep-link navigation from notifications.
/// Returns null if the booking no longer exists or is inaccessible.
final bookingDetailProvider =
    FutureProvider.autoDispose.family<Booking?, String>((ref, bookingId) {
  return ref.read(bookingsRepositoryProvider).getBookingById(bookingId);
});
