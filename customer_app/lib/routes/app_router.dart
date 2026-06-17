import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/app_navigation.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/otp_screen.dart';
import '../features/booking/screens/booking_screen.dart';
import '../features/address/screens/address_screen.dart';
import '../features/category/screens/subcategory_screen.dart';
import '../features/service/screens/services_screen.dart';
import '../features/service/screens/service_details_screen.dart';
import '../features/booking/screens/booking_success_screen.dart';
import '../features/bookings/screens/booking_details_screen.dart';
import '../features/profile/screens/edit_profile_screen.dart';
import '../features/wishlist/screens/wishlist_screen.dart';
import '../features/notifications/screens/notification_booking_screen.dart';
import '../features/cart/screens/cart_screen.dart';
import '../features/cart/screens/checkout_screen.dart';
import '../models/booking_model.dart';
import '../models/category_model.dart';
import '../models/subcategory_model.dart';
import '../models/service_model.dart';
import '../models/my_booking_model.dart';

class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String subcategory = '/subcategory/:categoryId';
  static const String services = '/services/:subcategoryId';
  static const String serviceDetail = '/service-detail/:serviceId';
  static const String booking = '/booking';
  static const String bookingSuccess = '/booking-success';
  static const String bookingDetail = '/booking-detail/:id';
  static const String notificationBooking = '/notification-booking/:id';
  static const String address = '/address';
  static const String editProfile = '/edit-profile';
  static const String wishlist = '/wishlist';
  static const String cart = '/cart';
  static const String checkout = '/cart/checkout';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const AppNavigation(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.otp,
      builder: (context, state) => const OtpScreen(),
    ),

    // Category → Subcategory
    GoRoute(
      path: AppRoutes.subcategory,
      builder: (context, state) {
        final category = state.extra;
        if (category is CategoryModel) return SubcategoryScreen(category: category);
        return const Scaffold(body: Center(child: Text('Category not found')));
      },
    ),

    // Subcategory → Services list
    GoRoute(
      path: AppRoutes.services,
      builder: (context, state) {
        final sub = state.extra;
        if (sub is SubcategoryModel) return ServicesScreen(subcategory: sub);
        return const Scaffold(body: Center(child: Text('Subcategory not found')));
      },
    ),

    // Services list → Service details
    GoRoute(
      path: AppRoutes.serviceDetail,
      builder: (context, state) {
        final service = state.extra;
        if (service is ServiceModel) return ServiceDetailsScreen(service: service);
        return const Scaffold(body: Center(child: Text('Service not found')));
      },
    ),

    // Service details → Booking flow
    GoRoute(
      path: AppRoutes.booking,
      builder: (context, state) {
        final service = state.extra;
        if (service is ServiceModel) return BookingScreen(service: service);
        return const Scaffold(body: Center(child: Text('Service not found')));
      },
    ),

    // Booking flow → Success page
    GoRoute(
      path: AppRoutes.bookingSuccess,
      builder: (context, state) {
        final booking = state.extra;
        if (booking is BookingModel) {
          return BookingSuccessScreen(
            booking: booking,
            onViewBookings: () => context.go(AppRoutes.home),
            onBackToHome: () => context.go(AppRoutes.home),
          );
        }
        return const Scaffold(body: Center(child: Text('Booking not found')));
      },
    ),

    // My Bookings → Booking Detail
    GoRoute(
      path: AppRoutes.bookingDetail,
      builder: (context, state) {
        final booking = state.extra;
        if (booking is MyBookingModel) {
          return BookingDetailsScreen(booking: booking);
        }
        return const Scaffold(body: Center(child: Text('Booking not found')));
      },
    ),

    // Notification deep-link → fetches booking by ID
    GoRoute(
      path: AppRoutes.notificationBooking,
      builder: (context, state) => NotificationBookingScreen(
        bookingId: state.pathParameters['id']!,
      ),
    ),

    GoRoute(
      path: AppRoutes.address,
      builder: (context, state) => const AddressScreen(),
    ),

    GoRoute(
      path: AppRoutes.editProfile,
      builder: (context, state) => const EditProfileScreen(),
    ),

    GoRoute(
      path: AppRoutes.wishlist,
      builder: (context, state) => const WishlistScreen(),
    ),

    GoRoute(
      path: AppRoutes.cart,
      builder: (context, state) => const CartScreen(),
    ),

    GoRoute(
      path: AppRoutes.checkout,
      builder: (context, state) => const CheckoutScreen(),
    ),
  ],
);
