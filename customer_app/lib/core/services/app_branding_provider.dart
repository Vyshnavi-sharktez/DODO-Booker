import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Streams the customer-app branding icon URL from Supabase Realtime.
/// Emits the current value immediately, then re-emits whenever an admin
/// updates the row — no app restart or invalidation needed.
/// Returns null when no icon is configured, falling back to the bundled asset.
final customerBrandingIconProvider = StreamProvider<String?>((ref) {
  return Supabase.instance.client
      .from('app_branding')
      .stream(primaryKey: ['app_id'])
      .eq('app_id', 'customer_app')
      .map((rows) => rows.isNotEmpty ? rows.first['icon_url'] as String? : null);
});
