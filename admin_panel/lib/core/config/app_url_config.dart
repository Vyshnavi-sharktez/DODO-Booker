import 'package:flutter/foundation.dart' show kIsWeb;

/// Resolves this app's base URL for use in Supabase auth redirects.
///
/// ─── Local development ────────────────────────────────────────────────────────
/// No configuration needed in code.  Flutter Web reads the actual dev-server
/// origin from the browser at runtime, so whatever port `flutter run` chose is
/// used automatically.
///
/// You MUST add a wildcard entry to your Supabase project once:
///   Auth → URL Configuration → Allowed Redirect URLs
///   → Add: http://localhost:*/reset-password
///
/// This tells Supabase to accept any localhost port as a valid redirect target,
/// so the dynamic port Flutter picks never causes a mismatch.
///
/// ─── Production builds ────────────────────────────────────────────────────────
/// Pass the deployed origin via --dart-define at build time:
///   flutter build web --dart-define=APP_BASE_URL=https://admin.yourdomain.com
///
/// Also add that URL to Supabase:
///   Auth → URL Configuration → Allowed Redirect URLs
///   → Add: https://admin.yourdomain.com/reset-password
///
/// ─── Vendor App ───────────────────────────────────────────────────────────────
/// The same pattern applies to any other Flutter Web app in this monorepo.
/// Copy this file and adjust the path constant if the reset route differs.
class AppUrlConfig {
  AppUrlConfig._();

  /// Injected at compile time via:
  ///   flutter run  --dart-define=APP_BASE_URL=https://admin.yourdomain.com
  ///   flutter build web --dart-define=APP_BASE_URL=https://admin.yourdomain.com
  ///
  /// Leave unset during local development — [_runtimeOrigin] is used instead.
  static const String _buildTimeBaseUrl =
      String.fromEnvironment('APP_BASE_URL');

  /// The current app origin, resolved at runtime (Flutter Web only).
  ///
  /// On web, [Uri.base] is the browser's `window.location.href`.
  /// Calling `.resolve('/')` strips any path so we get just the origin.
  ///   e.g. http://localhost:52341  or  https://admin.yourdomain.com
  static String get _runtimeOrigin {
    // resolve('/') on an absolute URI replaces the path with '/' keeping
    // scheme + host + port, then we remove the trailing slash.
    final origin = Uri.base.resolve('/').toString();
    // Strip trailing slash: "http://localhost:52341/" → "http://localhost:52341"
    return origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  }

  /// The effective base URL for this app.
  ///
  /// Precedence:
  ///   1. [_buildTimeBaseUrl] (set via --dart-define) — used in production
  ///   2. [_runtimeOrigin]   (Uri.base)               — used in local dev
  static String get baseUrl {
    if (_buildTimeBaseUrl.isNotEmpty) return _buildTimeBaseUrl;
    if (kIsWeb) return _runtimeOrigin;
    throw StateError(
      'APP_BASE_URL is not configured.\n'
      'For production builds pass --dart-define=APP_BASE_URL=https://yourdomain.com\n'
      'For local Flutter Web development no configuration is needed.',
    );
  }

  /// Full redirect URL sent to Supabase for password reset emails.
  ///
  /// This must match (or be covered by a wildcard) in your Supabase project's
  /// Auth → URL Configuration → Allowed Redirect URLs list.
  static String get passwordResetRedirectUrl => '$baseUrl/reset-password';
}
