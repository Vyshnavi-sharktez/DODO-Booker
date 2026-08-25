import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/app_navigation.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/otp_screen.dart';
import '../features/booking/screens/booking_screen.dart';
import '../features/address/screens/address_screen.dart';
import '../features/catalog/models/catalog_node_model.dart';
import '../features/catalog/screens/catalog_node_screen.dart';
import '../features/catalog/screens/category_explorer_screen.dart';
import '../features/category/screens/subcategory_screen.dart';
import '../features/service/screens/services_screen.dart';
import '../features/service/screens/category_services_screen.dart';
import '../features/booking/screens/booking_success_screen.dart';
import '../features/bookings/screens/booking_details_screen.dart';
import '../features/bookings/screens/my_bookings_screen.dart';
import '../features/bookings/utils/my_bookings_launcher.dart';
import '../features/amc/screens/amc_plans_page.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/edit_profile_screen.dart';
import '../features/wishlist/screens/wishlist_screen.dart';
import '../features/notifications/screens/notification_booking_screen.dart';
import '../features/cart/screens/cart_screen.dart';
import '../features/cart/screens/checkout_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/info/screens/contact_screen.dart';
import '../features/info/screens/help_screen.dart';
import '../features/info/screens/refund_policy_screen.dart';
import '../features/service_areas/screens/service_areas_screen.dart';
import '../models/booking_model.dart';
import '../models/category_model.dart';
import '../models/subcategory_model.dart';
import '../models/my_booking_model.dart';

class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String otp = '/otp';

  // ── Catalog Engine (Phase 3+) ──────────────────────────────────────────────
  static const String catalogNode = '/catalog/:nodeId';

  // ── Legacy browse routes ───────────────────────────────────────────────────
  static const String subcategory = '/subcategory/:categoryId';
  static const String services = '/services/:subcategoryId';
  static const String categoryServices = '/category-services/:categoryId';

  static const String categoryExplorer = '/category-explorer';

  static const String booking = '/booking';
  static const String bookingSuccess = '/booking-success';
  static const String bookingDetail = '/booking-detail/:id';
  static const String notificationBooking = '/notification-booking/:id';
  static const String address = '/address';
  static const String editProfile = '/edit-profile';
  static const String wishlist = '/wishlist';
  static const String cart = '/cart';
  static const String checkout = '/cart/checkout';
  static const String search = '/search';
  static const String myBookings = '/my-bookings';
  static const String amcPlans = '/amc-plans';
  static const String profile = '/profile';
  static const String serviceAreas = '/service-areas';
  static const String contact = '/contact';
  static const String help = '/help';
  static const String refundPolicy = '/refund-policy';
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

    // ── Catalog Engine ─────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.catalogNode,
      builder: (context, state) {
        final nodeId = state.pathParameters['nodeId']!;
        final extra = state.extra;
        if (extra is CatalogNodeModel) {
          return CatalogNodeScreen(node: extra);
        }
        // Deep-link fallback: fetch node by ID from the server.
        return CatalogNodeFetchScreen(nodeId: nodeId);
      },
    ),

    GoRoute(
      path: AppRoutes.categoryExplorer,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final node = extra?['node'] as CatalogNodeModel?;
        final categoryId = extra != null ? extra['categoryId'] as String? : null;
        final subId = extra != null ? extra['subId'] as String? : null;
        return CategoryExplorerScreen(
          initialCategoryId: node == null ? categoryId : null,
          initialSubId: node == null ? subId : null,
          initialNode: node,
        );
      },
    ),

    // Category → Subcategory (legacy — no longer navigated to from home)
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

    // Service details → Booking flow
    GoRoute(
      path: AppRoutes.booking,
      builder: (context, state) {
        final extra = state.extra;
        if (extra is CatalogNodeModel) return BookingScreen(service: extra);
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
            onViewBookings: booking.isAmc
                ? () => context.push(AppRoutes.amcPlans)
                : () => openMyBookings(context),
            onBackToHome: () => context.go(AppRoutes.home),
          );
        }
        return const Scaffold(body: Center(child: Text('Booking not found')));
      },
    ),

    // My Bookings → Booking Detail (mobile full-screen; desktop uses openBookingDetail launcher)
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
      path: AppRoutes.myBookings,
      builder: (context, state) => const MyBookingsScreen(),
    ),

    GoRoute(
      path: AppRoutes.amcPlans,
      builder: (context, state) => const AmcPlansPage(),
    ),

    GoRoute(
      path: AppRoutes.profile,
      builder: (context, state) => const ProfileScreen(),
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

    GoRoute(
      path: AppRoutes.search,
      builder: (context, state) => SearchScreen(
        initialQuery:
            state.extra is String ? state.extra as String : '',
      ),
    ),

    // Home category card → services filtered to that category
    GoRoute(
      path: AppRoutes.categoryServices,
      builder: (context, state) {
        final category = state.extra;
        if (category is CategoryModel) {
          return CategoryServicesScreen(category: category);
        }
        return const Scaffold(
          body: Center(child: Text('Category not found')),
        );
      },
    ),

    GoRoute(
      path: AppRoutes.contact,
      builder: (context, state) => const ContactScreen(),
    ),

    GoRoute(
      path: AppRoutes.help,
      builder: (context, state) => const HelpScreen(),
    ),

    GoRoute(
      path: AppRoutes.refundPolicy,
      builder: (context, state) => const RefundPolicyScreen(),
    ),

    GoRoute(
      path: AppRoutes.serviceAreas,
      builder: (context, state) => const ServiceAreasScreen(),
    ),
  ],
);
