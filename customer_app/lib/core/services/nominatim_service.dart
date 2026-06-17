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

    debugPrint('[DODO][Nominatim] city=$city state=${addr["state"]} pincode=${addr["postcode"]}');

    return NominatimAddress(
      line1: lineParts.isEmpty ? null : lineParts.join(', '),
      city: city,
      state: addr['state'] as String?,
      pincode: addr['postcode'] as String?,
    );
  }
}
