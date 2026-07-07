/// Flat search index entry for one customer.
///
/// Holds every lowercase searchable string gathered from the customer record,
/// their addresses, and all their bookings (services, categories, vendors).
/// [matches] is O(tokens) — always client-side, no network round-trips.
class CustomerSearchRecord {
  final String customerId;
  final List<String> _tokens;

  const CustomerSearchRecord({
    required this.customerId,
    required List<String> tokens,
  }) : _tokens = tokens;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    for (final t in _tokens) {
      if (t.contains(q)) return true;
    }
    return false;
  }
}
