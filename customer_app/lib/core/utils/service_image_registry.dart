/// Curated Unsplash fallback image URLs for service categories.
/// Priority order when resolving a service card image:
///   1. service.imageUrl  (from DB, set in admin panel)
///   2. ServiceImageRegistry.fallbackUrl(categoryName)  (keyword match)
///   3. errorBuilder icon gradient  (if network fails)
class ServiceImageRegistry {
  const ServiceImageRegistry._();

  // keyword (lowercase, partial) → Unsplash photo ID
  static const _map = <String, String>{
    // Cleaning & Housekeeping
    'clean': 'photo-1563453392212-326f5e854473',
    'housekeep': 'photo-1581578731548-c64695cc6952',
    'maid': 'photo-1581578731548-c64695cc6952',
    'sweep': 'photo-1563453392212-326f5e854473',
    'sofa': 'photo-1555041469-a586c61ea9bc',
    'upholst': 'photo-1555041469-a586c61ea9bc',
    'carpet': 'photo-1558618666-fcd25c85cd64',

    // Plumbing & Water
    'plumb': 'photo-1676210133055-eab6ef033ce3',
    'pipe': 'photo-1676210133055-eab6ef033ce3',
    'drain': 'photo-1676210133055-eab6ef033ce3',
    'tank': 'photo-1562016600-ece13e8ba570',
    'water': 'photo-1562016600-ece13e8ba570',
    'waterproof': 'photo-1562016600-ece13e8ba570',

    // Electrical & Tech
    'electr': 'photo-1621905251189-08b45d6a269e',
    'wir': 'photo-1621905251189-08b45d6a269e',
    'fan': 'photo-1621905251189-08b45d6a269e',
    'switch': 'photo-1621905251189-08b45d6a269e',
    'cctv': 'photo-1557597774-9d273605dfa9',
    'secur': 'photo-1557597774-9d273605dfa9',
    'solar': 'photo-1509391366360-2e959784a276',
    'internet': 'photo-1558618666-fcd25c85cd64',

    // Painting & Interiors
    'paint': 'photo-1562259949-e8e7689d7828',
    'wall': 'photo-1562259949-e8e7689d7828',
    'interior': 'photo-1618219908412-a29a1bb7b86e',
    'design': 'photo-1618219908412-a29a1bb7b86e',
    'decor': 'photo-1618219908412-a29a1bb7b86e',
    'modular': 'photo-1556909114-f6e7ad7d3136',

    // Carpentry & Flooring
    'carpen': 'photo-1601579112934-17ac2aa86292',
    'wood': 'photo-1601579112934-17ac2aa86292',
    'door': 'photo-1601579112934-17ac2aa86292',
    'window': 'photo-1558618666-fcd25c85cd64',
    'floor': 'photo-1581858726788-75bc0f6a952d',
    'tile': 'photo-1581858726788-75bc0f6a952d',
    'marble': 'photo-1581858726788-75bc0f6a952d',

    // Pest Control
    'pest': 'photo-1618220179428-22790b461013',
    'termite': 'photo-1618220179428-22790b461013',
    'mosquito': 'photo-1618220179428-22790b461013',

    // AC & Appliances
    'ac ': 'photo-1762341123870-d706f257a12e',
    'air con': 'photo-1762341123870-d706f257a12e',
    'hvac': 'photo-1762341123870-d706f257a12e',
    'appli': 'photo-1604689598793-b8bf1dc445a1',
    'refriger': 'photo-1604689598793-b8bf1dc445a1',
    'washing machine': 'photo-1604689598793-b8bf1dc445a1',

    // Packers & Movers
    'shift': 'photo-1600880292203-757bb62b4baf',
    'moving': 'photo-1600880292203-757bb62b4baf',
    'packer': 'photo-1600880292203-757bb62b4baf',
    'mover': 'photo-1600880292203-757bb62b4baf',
    'reloc': 'photo-1600880292203-757bb62b4baf',

    // Beauty & Wellness
    'salon': 'photo-1560869713-7d0a29430803',
    'beauty': 'photo-1560869713-7d0a29430803',
    'hair': 'photo-1560869713-7d0a29430803',
    'facial': 'photo-1544161515-4ab6ce6db874',
    'massage': 'photo-1544161515-4ab6ce6db874',
    'spa': 'photo-1544161515-4ab6ce6db874',
    'wax': 'photo-1560869713-7d0a29430803',
    'makeup': 'photo-1560869713-7d0a29430803',
    'bridal': 'photo-1560869713-7d0a29430803',
    'yoga': 'photo-1544367567-0f2fcb009e0b',
    'fitness': 'photo-1544367567-0f2fcb009e0b',

    // Laundry
    'laundry': 'photo-1604335399105-a0c585fd81a1',
    'wash': 'photo-1604335399105-a0c585fd81a1',
    'iron': 'photo-1604335399105-a0c585fd81a1',
    'dry clean': 'photo-1604335399105-a0c585fd81a1',

    // Gardening & Outdoor
    'garden': 'photo-1416879595882-3373a0480b5b',
    'plant': 'photo-1416879595882-3373a0480b5b',
    'lawn': 'photo-1416879595882-3373a0480b5b',
    'landscap': 'photo-1416879595882-3373a0480b5b',

    // Cooking & Kitchen
    'cook': 'photo-1556909114-f6e7ad7d3136',
    'chef': 'photo-1556909114-f6e7ad7d3136',
    'kitchen': 'photo-1556909114-f6e7ad7d3136',
    'catering': 'photo-1556909114-f6e7ad7d3136',
    'tiffin': 'photo-1556909114-f6e7ad7d3136',

    // Vehicle
    'car wash': 'photo-1532974297617-c0f05fe48bff',
    'vehicle': 'photo-1532974297617-c0f05fe48bff',
    'driver': 'photo-1449965408869-eaa3f722e40d',

    // Pet Care
    'pet': 'photo-1450778869180-41d0601e046e',
    'dog': 'photo-1450778869180-41d0601e046e',

    // General Repair & Home
    'repair': 'photo-1581092334247-ddef2a41e98e',
    'fix': 'photo-1581092334247-ddef2a41e98e',
    'maintenance': 'photo-1484154218784-c0501cbe55e6',
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

  /// Mobile-aware resolution: uses [mobileImageUrl] when set,
  /// falls back to [webImageUrl], then the keyword-based Unsplash fallback.
  static String resolveMobile(
    String? mobileImageUrl,
    String? webImageUrl,
    String? categoryName,
  ) {
    if (mobileImageUrl != null && mobileImageUrl.isNotEmpty) {
      return mobileImageUrl;
    }
    return resolve(webImageUrl, categoryName);
  }

  static String _build(String photoId) =>
      'https://images.unsplash.com/$photoId'
      '?auto=format&fit=crop&w=600&q=75';
}
