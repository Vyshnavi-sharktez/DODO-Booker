import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/nominatim_service.dart';
import '../../domain/models/vendor_serving_area.dart';

class VendorServingAreaDialog extends StatefulWidget {
  const VendorServingAreaDialog({super.key, this.existing});

  final VendorServingArea? existing;

  @override
  State<VendorServingAreaDialog> createState() =>
      _VendorServingAreaDialogState();
}

class _VendorServingAreaDialogState extends State<VendorServingAreaDialog> {
  static const _defaultCenter = LatLng(17.3850, 78.4867); // Hyderabad
  static const _streetZoom = 12.0;

  late final MapController _mapController;
  late final TextEditingController _searchCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _radiusCtrl;

  LatLng _center = _defaultCenter;
  double _radiusKm = 5.0;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  List<NominatimSearchResult> _searchResults = [];
  bool _searching = false;
  bool _showResults = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchCtrl = TextEditingController();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _cityCtrl = TextEditingController(text: ex?.city ?? '');
    _radiusCtrl = TextEditingController(
        text: ex != null ? ex.radiusKm.toStringAsFixed(1) : '5.0');
    if (ex != null) {
      _center = LatLng(ex.latitude, ex.longitude);
      _radiusKm = ex.radiusKm;
      _isActive = ex.isActive;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _radiusCtrl.dispose();
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
    _debounce = Timer(const Duration(milliseconds: 500), () => _doSearch(value));
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _showResults = true;
    });
    try {
      final results = await NominatimService().search(query);
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

  void _selectResult(NominatimSearchResult result) {
    final newCenter = LatLng(result.lat, result.lon);
    setState(() {
      _center = newCenter;
      _showResults = false;
      _searchCtrl.clear();
      if (_nameCtrl.text.isEmpty) {
        // Extract first segment of display_name as suggested name
        final parts = result.displayName.split(',');
        _nameCtrl.text = parts.first.trim();
      }
      if (_cityCtrl.text.isEmpty && result.city != null) {
        _cityCtrl.text = result.city!;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(newCenter, 13.0);
    });
  }

  void _onRadiusChanged(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) {
      setState(() => _radiusKm = parsed);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Area name is required.');
      return;
    }
    if (city.isEmpty) {
      setState(() => _error = 'City is required.');
      return;
    }
    if (_radiusKm <= 0) {
      setState(() => _error = 'Radius must be greater than 0.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final area = VendorServingArea(
      id: widget.existing?.id ?? '',
      name: name,
      city: city,
      latitude: _center.latitude,
      longitude: _center.longitude,
      radiusKm: _radiusKm,
      isActive: _isActive,
    );

    if (!mounted) return;
    Navigator.of(context).pop(area);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(),
                    if (_showResults) _buildSearchResults(),
                    const SizedBox(height: 14),
                    _buildMap(),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildNameField()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildCityField()),
                        const SizedBox(width: 12),
                        SizedBox(width: 130, child: _buildRadiusField()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildActiveToggle(),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isEdit = widget.existing != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            isEdit ? Icons.edit_location_alt_rounded : Icons.add_location_alt_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isEdit ? 'Edit Serving Area' : 'Add Serving Area',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search Location',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'e.g. KPHB, Hyderabad',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty && !_searching) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'No results found.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: _searchResults.map((r) {
          return InkWell(
            onTap: () => _selectResult(r),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.place_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
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
    );
  }

  Widget _buildMap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Map Preview',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(tap to reposition center)',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _streetZoom,
                onTap: (_, point) {
                  setState(() => _center = point);
                  _mapController.move(point, _mapController.camera.zoom);
                },
                onPositionChanged: (camera, _) {},
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.dodo.admin_panel',
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _center,
                      radius: _radiusKm * 1000.0,
                      useRadiusInMeter: true,
                      color: AppColors.primary.withAlpha(40),
                      borderColor: AppColors.primary,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _center,
                      width: 36,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_pin,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameCtrl,
      decoration: InputDecoration(
        labelText: 'Area Name *',
        hintText: 'e.g. KPHB',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildCityField() {
    return TextFormField(
      controller: _cityCtrl,
      decoration: InputDecoration(
        labelText: 'City *',
        hintText: 'e.g. Hyderabad',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildRadiusField() {
    return TextFormField(
      controller: _radiusCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      onChanged: _onRadiusChanged,
      decoration: InputDecoration(
        labelText: 'Radius (km) *',
        hintText: '5.0',
        suffixText: 'km',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildActiveToggle() {
    return Row(
      children: [
        Switch(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          activeThumbColor: AppColors.success,
        ),
        const SizedBox(width: 8),
        Text(
          _isActive ? 'Active — visible to vendors' : 'Inactive — hidden from vendors',
          style: TextStyle(
            fontSize: 13,
            color: _isActive ? AppColors.success : AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: Text(_saving ? 'Saving…' : 'Save Area'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
