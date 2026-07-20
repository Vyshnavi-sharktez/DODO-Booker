import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NominatimAddress {
  final String? line1;
  final String? city;
  final String? state;
  final String? pincode;

  const NominatimAddress({this.line1, this.city, this.state, this.pincode});
}

class NominatimSearchResult {
  final String displayName;
  final double lat;
  final double lon;
  final String? city;
  /// OSM place type — e.g. "suburb", "city", "town", "administrative".
  final String? placeType;

  const NominatimSearchResult({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.city,
    this.placeType,
  });
}

class NominatimService {
  static const _host = 'nominatim.openstreetmap.org';

  Future<NominatimAddress> reverseGeocode(double lat, double lng) async {
    final uri = Uri.https(_host, '/reverse', {
      'format': 'json',
      'lat': lat.toString(),
      'lon': lng.toString(),
      'accept-language': 'en',
    });

    debugPrint('[DODO][Nominatim] reverse → lat=$lat lng=$lng');
    final res = await http
        .get(uri, headers: {'User-Agent': 'DODO-Booker/1.0'})
        .timeout(const Duration(seconds: 8));
    debugPrint('[DODO][Nominatim] status: ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('Nominatim HTTP error: ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final addr = (body['address'] as Map<String, dynamic>?) ?? {};

    final houseNumber = (addr['house_number'] as String?) ?? '';
    final road = (addr['road'] as String?) ?? '';
    final suburb = (addr['suburb'] as String?)
        ?? (addr['neighbourhood'] as String?)
        ?? (addr['sublocality'] as String?)
        ?? '';

    final lineParts = <String>[
      if (houseNumber.isNotEmpty) houseNumber,
      if (road.isNotEmpty) road,
      if (suburb.isNotEmpty && road.isEmpty) suburb,
    ];

    final city = (addr['city'] as String?)
        ?? (addr['town'] as String?)
        ?? (addr['village'] as String?)
        ?? (addr['county'] as String?);

    return NominatimAddress(
      line1: lineParts.isEmpty ? null : lineParts.join(', '),
      city: city,
      state: addr['state'] as String?,
      pincode: addr['postcode'] as String?,
    );
  }

  /// Forward geocoding — searches for [query] and returns up to 8 results.
  /// Free via Nominatim/OpenStreetMap; no API key required.
  ///
  /// [countrycodes] — optional ISO 3166-1 alpha-2 code (e.g. 'in') to restrict
  /// results to a specific country. Helps surface suburb/neighbourhood results
  /// that would otherwise be ranked below the parent city.
  Future<List<NominatimSearchResult>> search(
    String query, {
    String? countrycodes,
  }) async {
    final params = <String, String>{
      'q': query,
      'format': 'json',
      'limit': '8',
      'accept-language': 'en',
      'addressdetails': '1',
    };
    if (countrycodes != null) params['countrycodes'] = countrycodes;
    final uri = Uri.https(_host, '/search', params);

    debugPrint('[DODO][Nominatim] search → "$query" countrycodes=$countrycodes');
    final res = await http
        .get(uri, headers: {'User-Agent': 'DODO-Booker/1.0'})
        .timeout(const Duration(seconds: 8));
    debugPrint('[DODO][Nominatim] search status: ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('Nominatim HTTP error: ${res.statusCode}');
    }

    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((item) {
      final m = item as Map<String, dynamic>;
      final addr = (m['address'] as Map<String, dynamic>?) ?? {};
      final city = (addr['city'] as String?)
          ?? (addr['town'] as String?)
          ?? (addr['village'] as String?)
          ?? (addr['county'] as String?);
      return NominatimSearchResult(
        displayName: m['display_name'] as String? ?? '',
        lat: double.parse(m['lat'] as String),
        lon: double.parse(m['lon'] as String),
        city: city,
        placeType: m['type'] as String?,
      );
    }).toList();
  }
}
