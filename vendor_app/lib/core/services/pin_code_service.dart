import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'nominatim_service.dart';

enum PinLookupStatus { idle, loading, found, notFound }

class PinCodeResult {
  final String pincode;
  final String district;
  final String state;
  final List<String> postOfficeNames;

  const PinCodeResult({
    required this.pincode,
    required this.district,
    required this.state,
    required this.postOfficeNames,
  });
}

class PinCodeService {
  static const _timeout = Duration(seconds: 8);

  Future<PinCodeResult?> lookup(String pincode) async {
    if (pincode.length != 6) return null;
    if (int.tryParse(pincode) == null) return null;
    try {
      final uri = Uri.parse(
        'https://api.postalpincode.in/pincode/$pincode',
      );
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) return null;
      final block = data[0] as Map<String, dynamic>;
      if (block['Status'] != 'Success') return null;
      final offices = block['PostOffice'] as List<dynamic>?;
      if (offices == null || offices.isEmpty) return null;
      final first = offices[0] as Map<String, dynamic>;
      return PinCodeResult(
        pincode: pincode,
        district: first['District'] as String? ?? '',
        state: first['State'] as String? ?? '',
        postOfficeNames: offices
            .map((o) => (o as Map<String, dynamic>)['Name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Manages PIN-code lookup lifecycle for any address form.
///
/// Handles debouncing, in-flight cancellation (version tokens), parallel
/// Nominatim coordinate lookup, and status transitions. Instantiate once
/// per form widget, call [onPinChanged] from the PIN field's listener, and
/// call [dispose] in the widget's [State.dispose].
class PinLookupController {
  PinLookupController();

  PinLookupStatus _status = PinLookupStatus.idle;
  PinLookupStatus get status => _status;

  Timer? _debounce;
  int _version = 0;

  // Tracks the last values filled by this controller so forms can detect
  // whether city/state/coords have been manually edited since the fill.
  String? lastFilledCity;
  String? lastFilledState;
  double? lastFilledLat;
  double? lastFilledLng;

  void dispose() {
    _debounce?.cancel();
    ++_version; // invalidate any in-flight request
  }

  /// Called by the form whenever the PIN field text changes.
  ///
  /// [isMounted]   — return `false` after the widget is disposed.
  /// [onPinActive] — called immediately (synchronously) when a new valid
  ///                 PIN starts loading. Clear stale PIN-sourced fields here.
  /// [onResult]    — called with address data and optional map coordinates
  ///                 when lookup succeeds. Always called with the latest PIN.
  /// [onFailed]    — called when the PIN returned no match or an API error.
  /// [onIdle]      — called when the PIN field becomes incomplete or empty.
  ///                 Clear stale PIN-sourced fields here.
  void onPinChanged(
    String pin, {
    required bool Function() isMounted,
    required VoidCallback onPinActive,
    required void Function(
            PinCodeResult result, double? lat, double? lng)
        onResult,
    required VoidCallback onFailed,
    required VoidCallback onIdle,
  }) {
    _debounce?.cancel();

    if (pin.length != 6 || int.tryParse(pin) == null) {
      if (_status != PinLookupStatus.idle) {
        _status = PinLookupStatus.idle;
        onIdle();
      }
      return;
    }

    // New valid PIN — update status and clear stale data immediately.
    _status = PinLookupStatus.loading;
    onPinActive();

    final version = ++_version;
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      // Start both requests in parallel.
      final pinFuture = PinCodeService().lookup(pin);
      final coordFuture = NominatimService().search(pin, countrycodes: 'in');

      final pinResult = await pinFuture;
      if (!isMounted() || version != _version) return;

      if (pinResult == null) {
        _status = PinLookupStatus.notFound;
        onFailed();
        return;
      }

      // Coords are best-effort; a failure must not block the address fill.
      double? lat, lng;
      try {
        final coords = await coordFuture;
        if (coords.isNotEmpty) {
          lat = coords.first.lat;
          lng = coords.first.lon;
        }
      } catch (_) {}

      if (!isMounted() || version != _version) return;

      _status = PinLookupStatus.found;
      lastFilledCity = pinResult.district;
      lastFilledState = pinResult.state;
      lastFilledLat = lat;
      lastFilledLng = lng;
      onResult(pinResult, lat, lng);
    });
  }
}
