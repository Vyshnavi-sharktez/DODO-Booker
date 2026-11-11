import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';

const _kBucket = 'vendor-requests';

class _DurationOption {
  _DurationOption({
    required this.durationMinutes,
    required this.price,
    required this.discountType,
    required this.discountValue,
  });
  final int durationMinutes;
  final double price;
  final String discountType;
  final double discountValue;

  String get autoLabel {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h hr';
    return '$h hr $m min';
  }

  double get activePrice {
    if (discountType == 'percentage' && discountValue > 0) {
      return price * (1 - discountValue / 100);
    }
    if (discountType == 'flat' && discountValue > 0) {
      return (price - discountValue).clamp(0.0, double.infinity);
    }
    return price;
  }
}

class AdminCreateServiceDialog extends StatefulWidget {
  const AdminCreateServiceDialog({
    super.key,
    required this.vendorId,
    required this.vendorName,
    required this.onCreated,
  });

  final String vendorId;
  final String vendorName;
  final VoidCallback onCreated;

  static Future<void> show(
    BuildContext context, {
    required String vendorId,
    required String vendorName,
    required VoidCallback onCreated,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminCreateServiceDialog(
        vendorId: vendorId,
        vendorName: vendorName,
        onCreated: onCreated,
      ),
    );
  }

  @override
  State<AdminCreateServiceDialog> createState() =>
      _AdminCreateServiceDialogState();
}

class _AdminCreateServiceDialogState extends State<AdminCreateServiceDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _warrantyDaysCtrl = TextEditingController();
  final _warrantyCoversCtrl = TextEditingController();
  final _warrantyExclusionsCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();

  String _pricingType = 'fixed';
  String _discountType = 'none';
  String? _selectedCategoryId;

  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true;

  bool? _hasSubscription; // null=loading, true=has, false=doesn't have

  final List<String> _includedItems = [];
  final List<String> _excludedItems = [];

  bool _warrantyEnabled = false;
  String? _warrantyError;

  final List<_DurationOption> _durationOptions = [];

  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _checkSubscription();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    _warrantyDaysCtrl.dispose();
    _warrantyCoversCtrl.dispose();
    _warrantyExclusionsCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await Supabase.instance.client
          .from('vendor_categories')
          .select('id, name')
          .eq('vendor_id', widget.vendorId)
          .order('name');
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data as List);
          _categoriesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  Future<void> _checkSubscription() async {
    try {
      final data = await Supabase.instance.client
          .from('vendor_subscriptions')
          .select('id, subscription_plans(id, permissions)')
          .eq('vendor_id', widget.vendorId)
          .eq('status', 'active')
          .maybeSingle();
      if (mounted) {
        final plan = data?['subscription_plans'] as Map<String, dynamic>?;
        final perms = (plan?['permissions'] as Map<String, dynamic>?) ?? {};
        final hasFeature = perms['allow_vendor_catalog'] == true;
        setState(() => _hasSubscription = data != null && hasFeature);
      }
    } catch (e) {
      if (mounted) setState(() => _hasSubscription = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final mime = const {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
        }[ext] ??
        'image/jpeg';
    final path =
        '${widget.vendorId}/${DateTime.now().millisecondsSinceEpoch}.$ext';

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.storage.from(_kBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      final url = Supabase.instance.client.storage
          .from(_kBucket)
          .getPublicUrl(path);
      if (mounted) setState(() => _imageCtrl.text = url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openAddDurationOption() {
    showDialog<_DurationOption?>(
      context: context,
      builder: (_) => const _DurationOptionDialog(),
    ).then((opt) {
      if (opt != null && mounted) setState(() => _durationOptions.add(opt));
    });
  }

  void _openEditDurationOption(int index) {
    showDialog<_DurationOption?>(
      context: context,
      builder: (_) => _DurationOptionDialog(existing: _durationOptions[index]),
    ).then((opt) {
      if (opt != null && mounted) {
        setState(() => _durationOptions[index] = opt);
      }
    });
  }

  void _addItem(List<String> list) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Item description'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => list.add(ctrl.text.trim()));
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Service name is required.');
      return;
    }

    if (_pricingType == 'duration_based') {
      if (_durationOptions.isEmpty) {
        setState(() => _error = 'Add at least one duration pricing option.');
        return;
      }
    } else {
      final priceText = _priceCtrl.text.trim();
      final parsedPrice = double.tryParse(priceText);
      if (priceText.isEmpty || parsedPrice == null || parsedPrice <= 0) {
        setState(() => _error = 'Enter a valid price greater than zero.');
        return;
      }
      if (_discountType != 'none') {
        final dv = double.tryParse(_discountCtrl.text.trim()) ?? 0;
        if (dv <= 0) {
          setState(() => _error = 'Enter a discount amount greater than zero.');
          return;
        }
        if (_discountType == 'percentage' && dv >= 100) {
          setState(() => _error = 'Percentage discount must be less than 100%.');
          return;
        }
        if (_discountType == 'fixed' && dv >= parsedPrice) {
          setState(() => _error = 'Fixed discount cannot exceed the price.');
          return;
        }
      }
    }

    if (_warrantyEnabled) {
      final days = int.tryParse(_warrantyDaysCtrl.text.trim());
      if (days == null || days <= 0) {
        setState(() => _warrantyError = 'Enter a valid warranty duration (days > 0).');
        return;
      }
    }
    setState(() => _warrantyError = null);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      double? price;
      double? activePrice;
      String submittedDiscountType = 'none';
      double submittedDiscountValue = 0;

      if (_pricingType == 'duration_based') {
        price = _durationOptions.map((o) => o.activePrice).reduce((a, b) => a < b ? a : b);
        activePrice = price;
      } else {
        price = double.tryParse(_priceCtrl.text.trim());
        submittedDiscountType = _discountType;
        submittedDiscountValue = _discountType != 'none'
            ? (double.tryParse(_discountCtrl.text.trim()) ?? 0)
            : 0;
        if (price != null) {
          if (_discountType == 'percentage' && submittedDiscountValue > 0) {
            activePrice = price * (1 - submittedDiscountValue / 100);
          } else if (_discountType == 'fixed' && submittedDiscountValue > 0) {
            activePrice = (price - submittedDiscountValue).clamp(0.0, double.infinity);
          } else {
            activePrice = price;
          }
        }
      }

      final warrantyDays =
          _warrantyEnabled ? int.tryParse(_warrantyDaysCtrl.text.trim()) : null;
      final imageUrl =
          _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim();

      final durationOptionsJson = _pricingType == 'duration_based'
          ? _durationOptions
              .map((o) => {
                    'duration_minutes': o.durationMinutes,
                    'price': o.price,
                    'discount_type': o.discountType,
                    'discount_value': o.discountValue,
                  })
              .toList()
          : <Map<String, dynamic>>[];

      await Supabase.instance.client.rpc('admin_create_custom_service', params: {
        'p_vendor_id': widget.vendorId,
        'p_service_name': name,
        if (_descCtrl.text.trim().isNotEmpty)
          'p_description': _descCtrl.text.trim(),
        'p_price': price,
        'p_active_price': activePrice,
        if (imageUrl != null) 'p_image_url': imageUrl,
        if (_selectedCategoryId != null)
          'p_vendor_category_id': _selectedCategoryId,
        'p_pricing_type': _pricingType,
        'p_discount_type': submittedDiscountType,
        'p_discount_value': submittedDiscountValue,
        if (_includedItems.isNotEmpty) 'p_included_items': _includedItems,
        if (_excludedItems.isNotEmpty) 'p_excluded_items': _excludedItems,
        'p_warranty_enabled': _warrantyEnabled,
        if (_warrantyEnabled && warrantyDays != null)
          'p_warranty_days': warrantyDays,
        if (_warrantyEnabled && _warrantyCoversCtrl.text.trim().isNotEmpty)
          'p_warranty_covers': _warrantyCoversCtrl.text.trim(),
        if (_warrantyEnabled && _warrantyExclusionsCtrl.text.trim().isNotEmpty)
          'p_warranty_exclusions': _warrantyExclusionsCtrl.text.trim(),
        'p_duration_options': durationOptionsJson,
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service created successfully.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to create service: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(child: SingleChildScrollView(child: _buildBody())),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Service',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  'for ${widget.vendorName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Subscription warning ────────────────────────────────────────
          if (_hasSubscription == false) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'No Active Customer Services Subscription',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF92400E)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'This vendor does not have an active subscription that includes '
                          'Customer Services. You can still create the service.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF78350F)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Category ───────────────────────────────────────────────────
          const _Label('Category'),
          const SizedBox(height: 6),
          _categoriesLoading
              ? const SizedBox(
                  height: 44,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : DropdownButtonFormField<String?>(
                  value: _selectedCategoryId,
                  decoration: const InputDecoration(
                      hintText: 'Select a category (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Uncategorized')),
                    ..._categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c['id'] as String,
                        child: Text(c['name'] as String),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedCategoryId = v),
                ),
          const SizedBox(height: 18),

          // ── Service name ───────────────────────────────────────────────
          const _Label('Service Name *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(hintText: 'e.g. AC Repair'),
          ),
          const SizedBox(height: 18),

          // ── Description ────────────────────────────────────────────────
          const _Label('Description'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Short description of the service…'),
          ),
          const SizedBox(height: 18),

          // ── Pricing Type ───────────────────────────────────────────────
          const _Label('Pricing Type *'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PricingTypeButton(
                  label: 'Fixed Price',
                  icon: Icons.currency_rupee_rounded,
                  selected: _pricingType == 'fixed',
                  onTap: () => setState(() {
                    _pricingType = 'fixed';
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PricingTypeButton(
                  label: 'Duration-Based',
                  icon: Icons.timer_outlined,
                  selected: _pricingType == 'duration_based',
                  onTap: () => setState(() {
                    _pricingType = 'duration_based';
                    _error = null;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Fixed pricing fields ───────────────────────────────────────
          if (_pricingType == 'fixed') ...[
            const _Label('Price (₹) *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(prefixText: '₹ ', hintText: '0'),
            ),
            const SizedBox(height: 14),
            const _Label('Discount Type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _discountType,
              items: const [
                DropdownMenuItem(
                    value: 'none', child: Text('No Discount')),
                DropdownMenuItem(
                    value: 'percentage', child: Text('Percentage Off')),
                DropdownMenuItem(
                    value: 'fixed', child: Text('Fixed Amount Off')),
              ],
              onChanged: (v) => setState(() {
                _discountType = v!;
                _discountCtrl.clear();
              }),
            ),
            if (_discountType != 'none') ...[
              const SizedBox(height: 14),
              _Label(
                  _discountType == 'percentage' ? 'Discount (%)' : 'Discount Amount (₹)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _discountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: InputDecoration(
                  prefixText: _discountType == 'percentage' ? '' : '₹ ',
                  suffixText:
                      _discountType == 'percentage' ? '%' : null,
                  hintText: '0',
                ),
              ),
            ],
            const SizedBox(height: 18),
          ],

          // ── Duration pricing ───────────────────────────────────────────
          if (_pricingType == 'duration_based') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Label('Duration Pricing Options *'),
                TextButton.icon(
                  onPressed: _openAddDurationOption,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_durationOptions.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.border.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No options yet. Tap Add to create a pricing option.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              )
            else
              ...List.generate(_durationOptions.length, (i) {
                final opt = _durationOptions[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(opt.autoLabel,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '₹${opt.price.toStringAsFixed(0)}'
                              '${opt.discountType != 'none' ? (opt.discountType == 'percentage' ? ' (${opt.discountValue.toStringAsFixed(0)}% off)' : ' (₹${opt.discountValue.toStringAsFixed(0)} off)') : ''}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _openEditDurationOption(i),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        color: AppColors.textSecondary,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _durationOptions.removeAt(i)),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        color: AppColors.error,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 18),
          ],

          // ── Image ──────────────────────────────────────────────────────
          const _Label('Service Image'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _imageCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Image URL or upload'),
                ),
              ),
              const SizedBox(width: 10),
              _uploading
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      onPressed: _pickAndUpload,
                      icon: const Icon(Icons.upload_rounded),
                      tooltip: 'Upload image',
                      color: AppColors.primary,
                    ),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _imageCtrl,
            builder: (context, val, _) {
              final url = val.text.trim();
              if (url.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 48,
                      color: AppColors.border,
                      alignment: Alignment.center,
                      child: const Text('Invalid URL',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),

          // ── Included items ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _Label("What's Included"),
              TextButton.icon(
                onPressed: () => _addItem(_includedItems),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_includedItems.isEmpty)
            const Text('Nothing added yet.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(
                _includedItems.length,
                (i) => Chip(
                  label: Text(_includedItems[i],
                      style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () =>
                      setState(() => _includedItems.removeAt(i)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          const SizedBox(height: 14),

          // ── Excluded items ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _Label("What's Not Included"),
              TextButton.icon(
                onPressed: () => _addItem(_excludedItems),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_excludedItems.isEmpty)
            const Text('Nothing added yet.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(
                _excludedItems.length,
                (i) => Chip(
                  label: Text(_excludedItems[i],
                      style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () =>
                      setState(() => _excludedItems.removeAt(i)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          const SizedBox(height: 18),

          // ── Warranty ───────────────────────────────────────────────────
          Row(
            children: [
              Switch(
                value: _warrantyEnabled,
                onChanged: (v) => setState(() {
                  _warrantyEnabled = v;
                  _warrantyError = null;
                }),
                activeTrackColor: AppColors.success,
                activeThumbColor: Colors.white,
              ),
              const SizedBox(width: 8),
              const _Label('Warranty'),
            ],
          ),
          if (_warrantyEnabled) ...[
            const SizedBox(height: 10),
            const _Label('Warranty Duration (days) *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _warrantyDaysCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: '30'),
            ),
            const SizedBox(height: 14),
            const _Label("What's Covered"),
            const SizedBox(height: 6),
            TextFormField(
              controller: _warrantyCoversCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: 'Describe what the warranty covers…'),
            ),
            const SizedBox(height: 14),
            const _Label('Exclusions'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _warrantyExclusionsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: "Describe what's not covered…"),
            ),
            if (_warrantyError != null) ...[
              const SizedBox(height: 10),
              _ErrorBanner(message: _warrantyError!),
            ],
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving || _uploading ? null : _save,
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create Service'),
          ),
        ],
      ),
    );
  }
}

// ── Duration option dialog ────────────────────────────────────────────────────

class _DurationOptionDialog extends StatefulWidget {
  const _DurationOptionDialog({this.existing});
  final _DurationOption? existing;

  @override
  State<_DurationOptionDialog> createState() => _DurationOptionDialogState();
}

class _DurationOptionDialogState extends State<_DurationOptionDialog> {
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discountCtrl;
  late String _discountType;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _minutesCtrl =
        TextEditingController(text: e != null ? '${e.durationMinutes}' : '');
    _priceCtrl = TextEditingController(
        text: e != null ? e.price.toStringAsFixed(0) : '');
    _discountType = e?.discountType ?? 'none';
    _discountCtrl = TextEditingController(
        text: e != null && e.discountType != 'none'
            ? e.discountValue.toStringAsFixed(0)
            : '');
  }

  @override
  void dispose() {
    _minutesCtrl.dispose();
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final minutes = int.tryParse(_minutesCtrl.text.trim());
    if (minutes == null || minutes <= 0) {
      setState(() => _error = 'Enter a valid duration in minutes.');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    double discountValue = 0;
    if (_discountType != 'none') {
      discountValue = double.tryParse(_discountCtrl.text.trim()) ?? 0;
      if (discountValue <= 0) {
        setState(() => _error = 'Enter a discount amount greater than zero.');
        return;
      }
    }
    Navigator.of(context).pop(_DurationOption(
      durationMinutes: minutes,
      price: price,
      discountType: _discountType,
      discountValue: discountValue,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Duration Option' : 'Edit Duration Option'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Label('Duration (minutes) *'),
            const SizedBox(height: 6),
            TextField(
              controller: _minutesCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: '60'),
            ),
            const SizedBox(height: 14),
            const _Label('Price (₹) *'),
            const SizedBox(height: 6),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(prefixText: '₹ ', hintText: '0'),
            ),
            const SizedBox(height: 14),
            const _Label('Discount Type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _discountType,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('No Discount')),
                DropdownMenuItem(
                    value: 'percentage', child: Text('Percentage Off')),
                DropdownMenuItem(
                    value: 'flat', child: Text('Flat Amount Off')),
              ],
              onChanged: (v) => setState(() {
                _discountType = v!;
                _discountCtrl.clear();
              }),
            ),
            if (_discountType != 'none') ...[
              const SizedBox(height: 14),
              _Label(_discountType == 'percentage'
                  ? 'Discount (%)'
                  : 'Discount Amount (₹)'),
              const SizedBox(height: 6),
              TextField(
                controller: _discountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: InputDecoration(
                  prefixText:
                      _discountType == 'percentage' ? '' : '₹ ',
                  suffixText:
                      _discountType == 'percentage' ? '%' : null,
                  hintText: '0',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _PricingTypeButton extends StatelessWidget {
  const _PricingTypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFCBD5E0),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
