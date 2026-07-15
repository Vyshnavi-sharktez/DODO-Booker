import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/customer.dart';
import '../domain/models/customer_address.dart';
import '../domain/models/customer_profile.dart';

class CustomerProfileRepository {
  final SupabaseClient _supabase;
  const CustomerProfileRepository(this._supabase);

  static const _bookingSelect = '''
    id,
    booking_number,
    vendor_id,
    dodo_team_id,
    assignment_type,
    service_date,
    status,
    subtotal,
    discount_amount,
    total_amount,
    address,
    notes,
    created_at,
    vendors(id, business_name),
    dodo_teams(id, team_name),
    customer_reviews!booking_id(id, rating, review_text, created_at),
    booking_items(
      service_id,
      quantity,
      unit_price,
      total_price,
      catalog_nodes!booking_items_service_id_catalog_fkey(id, name)
    )
  ''';

  Future<CustomerProfile> fetchCustomerProfile(String customerId) async {
    final results = await Future.wait<dynamic>([
      _supabase.from('customers').select().eq('id', customerId).single(),
      _supabase
          .from('customer_addresses')
          .select()
          .eq('customer_id', customerId)
          .order('is_default', ascending: false),
      _supabase
          .from('bookings')
          .select(_bookingSelect)
          .eq('customer_id', customerId)
          .order('created_at', ascending: false),
    ]);

    final customer =
        Customer.fromMap(results[0] as Map<String, dynamic>);
    final addresses = (results[1] as List<dynamic>)
        .map((r) => CustomerAddress.fromMap(r as Map<String, dynamic>))
        .toList();
    final bookings = (results[2] as List<dynamic>)
        .map((r) => CustomerBooking.fromMap(r as Map<String, dynamic>))
        .toList();

    return CustomerProfile(
      customer: customer,
      addresses: addresses,
      bookings: bookings,
    );
  }
}
