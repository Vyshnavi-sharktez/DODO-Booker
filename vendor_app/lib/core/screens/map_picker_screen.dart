import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../services/nominatim_service.dart';

class MapPickerResult {
  final double latitude;
  final double longitude;
  final String? line1;
  final String? city;
  final String? state;
  final String? pincode;

  const MapPickerResult({
    required this.latitude,
    required this.longitude,
    this.line1,
    this.city,
    this.state,
    this.pincode,
  });
}

class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const MapPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _fallback = LatLng(17.3850, 78.4867);
  static const _streetZoom = 13.0;

  late final MapController _mapController;
  late LatLng _selectedLatLng;
  double _currentZoom = _streetZoom;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLatLng =
          LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _currentZoom = 15;
    } else {
      _selectedLatLng = _fallback;
      _tryJumpToCurrentLocation();
    }
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
      final addr = await NominatimService()
          .reverseGeocode(_selectedLatLng.latitude, _selectedLatLng.longitude);
      if (!mounted) return;
      Navigator.of(context).pop(MapPickerResult(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
        line1: addr.line1,
        city: addr.city,
        state: addr.state,
        pincode: addr.pincode,
      ));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(MapPickerResult(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pick Location'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dodo.vendor_app',
              ),
            ],
          ),

          // Fixed crosshair — touches pass through to the map.
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_pin,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_selectedLatLng.latitude.toStringAsFixed(5)},  '
                    '${_selectedLatLng.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Drag or tap to position the pin on your location',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _isConfirming ? null : _confirm,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: AppColors.primary,
                    ),
                    child: _isConfirming
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Confirm Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
