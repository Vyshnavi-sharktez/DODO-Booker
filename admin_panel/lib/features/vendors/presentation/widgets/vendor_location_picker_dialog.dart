import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/nominatim_service.dart';

class VendorLocationPickerResult {
  final double latitude;
  final double longitude;
  final String? city;
  final String? address;

  const VendorLocationPickerResult({
    required this.latitude,
    required this.longitude,
    this.city,
    this.address,
  });
}

class VendorLocationPickerDialog extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const VendorLocationPickerDialog({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<VendorLocationPickerDialog> createState() =>
      _VendorLocationPickerDialogState();
}

class _VendorLocationPickerDialogState
    extends State<VendorLocationPickerDialog> {
  static const _fallback = LatLng(17.3850, 78.4867);
  static const _streetZoom = 13.0;

  late final MapController _mapController;
  late final TextEditingController _searchCtrl;
  late LatLng _selectedLatLng;
  double _currentZoom = _streetZoom;
  bool _isConfirming = false;

  List<NominatimSearchResult> _searchResults = [];
  bool _searching = false;
  bool _showResults = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchCtrl = TextEditingController();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLatLng =
          LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _currentZoom = 15;
    } else {
      _selectedLatLng = _fallback;
      _tryJumpToCurrentLocation();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 500), () => _doSearch(value));
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _showResults = true;
    });
    try {
      final results =
          await NominatimService().search(query, countrycodes: 'in');
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  void _selectSearchResult(NominatimSearchResult result) {
    final newCenter = LatLng(result.lat, result.lon);
    setState(() {
      _selectedLatLng = newCenter;
      _showResults = false;
      _searchResults = [];
      _searchCtrl.text = result.displayName;
    });
    try {
      _mapController.move(newCenter, 15);
    } catch (_) {}
  }

  Future<void> _tryJumpToCurrentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
    } catch (_) {}
  }

  Future<void> _confirm() async {
    setState(() => _isConfirming = true);
    try {
      final addr = await NominatimService().reverseGeocode(
        _selectedLatLng.latitude,
        _selectedLatLng.longitude,
      );
      if (!mounted) return;
      Navigator.of(context).pop(VendorLocationPickerResult(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
        city: addr.city,
        address: addr.line1,
      ));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(VendorLocationPickerResult(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.map_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Pick Location',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Map
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedLatLng,
                      initialZoom: _currentZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onTap: (_, point) {
                        _mapController.move(point, _currentZoom);
                      },
                      onPositionChanged: (camera, _) {
                        setState(() {
                          _selectedLatLng = camera.center;
                          _currentZoom = camera.zoom;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.dodo.admin_panel',
                      ),
                    ],
                  ),
                  // Fixed crosshair — touch passes through to map.
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_pin,
                            size: 40,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // Search Bar Overlay
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(30),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'e.g. KPHB Colony, Hyderabad',
                              hintStyle: const TextStyle(fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : _searchCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 18),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() {
                                              _searchResults = [];
                                              _showResults = false;
                                            });
                                          },
                                        )
                                      : null,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_showResults)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(30),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _searchResults.isEmpty && !_searching
                                    ? [
                                        const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                            'No results found.',
                                            style: TextStyle(
                                                fontSize: 13, color: AppColors.textSecondary),
                                          ),
                                        ),
                                      ]
                                    : _searchResults.map((r) {
                                        return InkWell(
                                          onTap: () => _selectSearchResult(r),
                                          borderRadius: BorderRadius.circular(10),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.place_rounded,
                                                    size: 16, color: AppColors.primary),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    r.displayName,
                                                    style: const TextStyle(
                                                        fontSize: 13, color: AppColors.textPrimary),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Bottom bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedLatLng.latitude.toStringAsFixed(5)},  '
                      '${_selectedLatLng.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed:
                        _isConfirming ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isConfirming ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: _isConfirming
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Select Location'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
