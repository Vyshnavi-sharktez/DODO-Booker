/// Curated Unsplash fallback image URLs for service categories.
/// Priority order when resolving a service card image:
///   1. service.imageUrl  (from DB, set in admin panel)
///   2. ServiceImageRegistry.fallbackUrl(categoryName)  (keyword match)
///   3. errorBuilder icon gradient  (if network fails)
class ServiceImageRegistry {
  const ServiceImageRegistry._();

  // keyword (lowercase, partial) → Unsplash photo ID
  static const _map = <String, String>{
    'clean': 'photo-1563453392212-326f5e854473',
    'plumb': 'photo-1676210133055-eab6ef033ce3',
    'electr': 'photo-1621905251189-08b45d6a269e',
    'paint': 'photo-1562259949-e8e7689d7828',
    'carpen': 'photo-1601579112934-17ac2aa86292',
    'pest': 'photo-1618220179428-22790b461013',
    'ac': 'photo-1762341123870-d706f257a12e',
    'appli': 'photo-1604689598793-b8bf1dc445a1',
    'shift': 'photo-1600880292203-757bb62b4baf',
    'moving': 'photo-1600880292203-757bb62b4baf',
    'salon': 'photo-1560869713-7d0a29430803',
    'beauty': 'photo-1560869713-7d0a29430803',
    'laundry': 'photo-1604335399105-a0c585fd81a1',
    'garden': 'photo-1416879595882-3373a0480b5b',
    'repair': 'photo-1581092334247-ddef2a41e98e',
    'home': 'photo-1484154218784-c0501cbe55e6',
  };

  static const _default = 'photo-1484154218784-c0501cbe55e6';

  /// Returns the best-match fallback Unsplash URL for [categoryName].
  /// Returns the generic home-services photo when no keyword matches.
  static String fallbackUrl(String? categoryName) {
    if (categoryName != null && categoryName.isNotEmpty) {
      final lower = categoryName.toLowerCase();
      for (final entry in _map.entries) {
        if (lower.contains(entry.key)) return _build(entry.value);
      }
    }
    return _build(_default);
  }

  /// Returns [imageUrl] if non-null and non-empty, otherwise the
  /// category-based Unsplash fallback.
  static String resolve(String? imageUrl, String? categoryName) {
    if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
    return fallbackUrl(categoryName);
  }

  static String _build(String photoId) =>
      'https://images.unsplash.com/$photoId'
      '?auto=format&fit=crop&w=600&q=75';
}
