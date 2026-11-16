/// Describes the search context the navbar search bar operates in.
///
/// Passed as an immutable constructor parameter through AppHeader →
/// NavSearchBar/NavSearchButton → _NavSearchCore → _SearchPanel.
/// No global state, no route observers — the scope is fixed for the
/// lifetime of each AppHeader instance and naturally resets on navigation.
sealed class SearchScope {
  const SearchScope();
}

/// Default: searches across all DODO catalog nodes and all vendor services.
class GlobalSearchScope extends SearchScope {
  const GlobalSearchScope();
}

/// Active while VendorListScreen is showing (desktop only).
/// Searches the cached vendor list for the given category in-memory.
class VendorListSearchScope extends SearchScope {
  const VendorListSearchScope({
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;
}

/// Active while VendorDetailScreen is showing (desktop only).
/// Searches that vendor's services in-memory using the existing
/// vendorVcsProvider cache key (vendorId, categoryId: null).
class VendorDetailSearchScope extends SearchScope {
  const VendorDetailSearchScope({
    required this.vendorId,
    required this.vendorName,
  });

  final String vendorId;
  final String vendorName;
  // categoryId is intentionally omitted: VendorDetailScreen always
  // calls vendorVcsProvider with categoryId: null, so we must match
  // that exact cache key to avoid a duplicate RPC call.
}
