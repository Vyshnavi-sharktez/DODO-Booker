import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/customer_search_record.dart';

/// Builds a flat search index for the customers list page in a single query.
///
/// Joins customers → addresses → bookings → booking_items → catalog_nodes /
/// vendors / dodo_teams so that the page can filter by any of those fields
/// entirely client-side.
class CustomerSearchRepository {
  final SupabaseClient _supabase;
  const CustomerSearchRepository(this._supabase);

  static const _select = '''
    id,
    full_name,
    phone,
    email,
    customer_addresses(city, address_line_1, address_line_2),
    bookings(
      id,
      booking_number,
      status,
      vendors(business_name),
      dodo_teams(team_name),
      booking_items(
        catalog_nodes!booking_items_service_id_catalog_fkey(name)
      )
    )
  ''';

  Future<Map<String, CustomerSearchRecord>> fetchSearchIndex() async {
    final data = await _supabase.from('customers').select(_select);
    final index = <String, CustomerSearchRecord>{};
    for (final row in data as List<dynamic>) {
      final record = _buildRecord(row as Map<String, dynamic>);
      index[record.customerId] = record;
    }
    return index;
  }

  CustomerSearchRecord _buildRecord(Map<String, dynamic> map) {
    final tokens = <String>[];

    void add(String? s) {
      if (s != null && s.isNotEmpty) tokens.add(s.toLowerCase());
    }

    add(map['id'] as String?);
    add(map['full_name'] as String?);
    add(map['phone'] as String?);
    add(map['email'] as String?);

    for (final addr in (map['customer_addresses'] as List<dynamic>? ?? [])) {
      final a = addr as Map<String, dynamic>;
      add(a['city'] as String?);
      add(a['address_line_1'] as String?);
      add(a['address_line_2'] as String?);
    }

    for (final b in (map['bookings'] as List<dynamic>? ?? [])) {
      final booking = b as Map<String, dynamic>;
      add(booking['id'] as String?);
      add(booking['booking_number'] as String?);
      add(booking['status'] as String?);
      final vendor = booking['vendors'] as Map<String, dynamic>?;
      add(vendor?['business_name'] as String?);
      final dodoTeam = booking['dodo_teams'] as Map<String, dynamic>?;
      add(dodoTeam?['team_name'] as String?);
      for (final item in (booking['booking_items'] as List<dynamic>? ?? [])) {
        final i = item as Map<String, dynamic>;
        final node = i['catalog_nodes'] as Map<String, dynamic>?;
        add(node?['name'] as String?);
      }
    }

    return CustomerSearchRecord(
        customerId: map['id'] as String, tokens: tokens);
  }
}
