import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';

// ── Local attribute models ──────────────────────────────────────────────────

class _AttrOption {
  final String id;
  final String optionName;
  final double priceAdjustment;
  final String discountType;
  final double discountValue;

  const _AttrOption({
    required this.id,
    required this.optionName,
    required this.priceAdjustment,
    required this.discountType,
    required this.discountValue,
  });

  factory _AttrOption.fromMap(Map<String, dynamic> m) => _AttrOption(
        id: m['id'] as String,
        optionName: m['option_name'] as String? ?? '',
        priceAdjustment: (m['price_adjustment'] as num?)?.toDouble() ?? 0.0,
        discountType: m['discount_type'] as String? ?? 'percentage',
        discountValue: (m['discount_value'] as num?)?.toDouble() ?? 0.0,
      );
}

class _Attr {
  final String id;
  final String name;
  final List<_AttrOption> options;

  const _Attr({required this.id, required this.name, required this.options});

  factory _Attr.fromMap(Map<String, dynamic> m) => _Attr(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        options: ((m['service_attribute_options'] as List<dynamic>?) ?? [])
            .map((e) => _AttrOption.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// VendorServiceConfigDialog
// ═══════════════════════════════════════════════════════════════════════════════

class VendorServiceConfigDialog extends StatefulWidget {
  final String serviceId;
  final String serviceName;

  const VendorServiceConfigDialog({
    super.key,
    required this.serviceId,
    required this.serviceName,
  });

  @override
  State<VendorServiceConfigDialog> createState() =>
      _VendorServiceConfigDialogState();
}

class _VendorServiceConfigDialogState extends State<VendorServiceConfigDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = Supabase.instance.client;

  // Pending edit proposal (non-null once an edit_service row is created/found)
  String? _pendingEditId;

  // Content state
  bool _contentLoading = true;
  bool _contentSaving = false;
  String? _contentError;
  List<String> _includedItems = [];
  List<String> _excludedItems = [];
  List<Map<String, String>> _beforeAfterPairs = [];

  // Warranty state
  bool _warrantyEnabled = false;
  final _warrantyDaysCtrl = TextEditingController();
  final _warrantyCoversCtrl = TextEditingController();
  final _warrantyExclusionsCtrl = TextEditingController();
  bool _warrantySaving = false;
  String? _warrantyError;

  // Attributes state
  bool _attrsLoading = true;
  List<_Attr> _attrs = [];

  // Live (approved) snapshots – used to detect which tabs have pending diffs.
  // Populated only when a pending proposal exists.
  List<String>? _liveIncluded;
  List<String>? _liveExcluded;
  List<Map<String, String>>? _liveBeforeAfter;
  bool? _liveWarrantyEnabled;
  int? _liveWarrantyDays;
  String? _liveWarrantyCovers;
  String? _liveWarrantyExclusions;
  List<_Attr>? _liveAttrs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadContent(); // chains to _loadAttrs() so _pendingEditId is resolved first
  }

  @override
  void dispose() {
    _tabController.dispose();
    _warrantyDaysCtrl.dispose();
    _warrantyCoversCtrl.dispose();
    _warrantyExclusionsCtrl.dispose();
    super.dispose();
  }

  // ── Content ────────────────────────────────────────────────────────────────

  Future<void> _loadContent() async {
    try {
      // Check for an existing pending edit_service proposal for this service.
      final proposalRows = await _db
          .from('vendor_service_requests')
          .select('id, included_items, excluded_items, before_after_pairs, '
              'warranty_enabled, warranty_days, warranty_covers, warranty_exclusions')
          .eq('parent_request_id', widget.serviceId)
          .eq('request_type', 'edit_service')
          .eq('status', 'pending')
          .limit(1);

      final Map<String, dynamic> row;
      if (proposalRows.isNotEmpty) {
        row = Map<String, dynamic>.from(proposalRows.first);
        _pendingEditId = row['id'] as String;

        // Fetch the live parent so we can detect per-tab diffs.
        final liveRow = await _db
            .from('vendor_service_requests')
            .select('included_items, excluded_items, before_after_pairs, '
                'warranty_enabled, warranty_days, warranty_covers, warranty_exclusions')
            .eq('id', widget.serviceId)
            .single();
        _liveIncluded =
            List<String>.from((liveRow['included_items'] as List?) ?? []);
        _liveExcluded =
            List<String>.from((liveRow['excluded_items'] as List?) ?? []);
        _liveBeforeAfter = ((liveRow['before_after_pairs'] as List?) ?? [])
            .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
            .toList();
        _liveWarrantyEnabled =
            (liveRow['warranty_enabled'] as bool?) ?? false;
        _liveWarrantyDays = liveRow['warranty_days'] as int?;
        _liveWarrantyCovers = liveRow['warranty_covers'] as String?;
        _liveWarrantyExclusions = liveRow['warranty_exclusions'] as String?;
      } else {
        row = await _db
            .from('vendor_service_requests')
            .select('included_items, excluded_items, before_after_pairs, '
                'warranty_enabled, warranty_days, warranty_covers, warranty_exclusions')
            .eq('id', widget.serviceId)
            .single();
      }

      if (!mounted) return;
      setState(() {
        _includedItems =
            List<String>.from((row['included_items'] as List<dynamic>?) ?? []);
        _excludedItems =
            List<String>.from((row['excluded_items'] as List<dynamic>?) ?? []);
        _beforeAfterPairs =
            ((row['before_after_pairs'] as List<dynamic>?) ?? [])
                .map((e) => Map<String, String>.from((e as Map)
                    .map((k, v) => MapEntry(k.toString(), v.toString()))))
                .toList();
        _warrantyEnabled = (row['warranty_enabled'] as bool?) ?? false;
        _warrantyDaysCtrl.text =
            row['warranty_days'] != null ? row['warranty_days'].toString() : '';
        _warrantyCoversCtrl.text = (row['warranty_covers'] as String?) ?? '';
        _warrantyExclusionsCtrl.text =
            (row['warranty_exclusions'] as String?) ?? '';
        _contentLoading = false;
      });
      _loadAttrs();
    } catch (_) {
      if (mounted) {
        setState(() => _contentLoading = false);
        _loadAttrs();
      }
    }
  }

  /// Returns the pending edit proposal ID, creating one if it doesn't exist yet.
  /// Copies all parent content/warranty and attributes into the new proposal row.
  Future<String> _ensureProposal() async {
    if (_pendingEditId != null) return _pendingEditId!;

    // Fetch current parent data to seed the proposal.
    final parent = await _db
        .from('vendor_service_requests')
        .select('vendor_id, service_name, description, price, active_price, '
            'image_url, included_items, excluded_items, before_after_pairs, '
            'warranty_enabled, warranty_days, warranty_covers, warranty_exclusions')
        .eq('id', widget.serviceId)
        .single();

    final proposalRow = await _db.from('vendor_service_requests').insert({
      'vendor_id': parent['vendor_id'],
      'service_name': parent['service_name'],
      'description': parent['description'],
      'price': parent['price'],
      'active_price': parent['active_price'],
      'image_url': parent['image_url'],
      'included_items': parent['included_items'] ?? [],
      'excluded_items': parent['excluded_items'] ?? [],
      'before_after_pairs': parent['before_after_pairs'] ?? [],
      'warranty_enabled': parent['warranty_enabled'] ?? false,
      'warranty_days': parent['warranty_days'],
      'warranty_covers': parent['warranty_covers'],
      'warranty_exclusions': parent['warranty_exclusions'],
      'request_type': 'edit_service',
      'status': 'pending',
      'parent_request_id': widget.serviceId,
    }).select('id').single();

    final proposalId = proposalRow['id'] as String;

    // Seed live snapshots from parent (proposal starts as an exact copy).
    _liveIncluded =
        List<String>.from((parent['included_items'] as List?) ?? []);
    _liveExcluded =
        List<String>.from((parent['excluded_items'] as List?) ?? []);
    _liveBeforeAfter = ((parent['before_after_pairs'] as List?) ?? [])
        .map((e) => Map<String, String>.from(
            (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
        .toList();
    _liveWarrantyEnabled = (parent['warranty_enabled'] as bool?) ?? false;
    _liveWarrantyDays = parent['warranty_days'] as int?;
    _liveWarrantyCovers = parent['warranty_covers'] as String?;
    _liveWarrantyExclusions = parent['warranty_exclusions'] as String?;

    // Copy parent's service_attributes into the proposal.
    final parentAttrs = await _db
        .from('service_attributes')
        .select('*, service_attribute_options(id, option_name, price_adjustment, '
            'sort_order, discount_type, discount_value)')
        .eq('custom_service_id', widget.serviceId);

    final parentAttrsList = parentAttrs as List;
    final liveAttrsList = parentAttrsList
        .map((e) => _Attr.fromMap(e as Map<String, dynamic>))
        .toList();

    for (final attr in parentAttrsList) {
      final newAttr = await _db.from('service_attributes').insert({
        'custom_service_id': proposalId,
        'name': attr['name'],
        'field_type': attr['field_type'],
        'is_required': attr['is_required'],
      }).select('id').single();
      for (final opt in (attr['service_attribute_options'] as List<dynamic>? ?? [])) {
        await _db.from('service_attribute_options').insert({
          'attribute_id': newAttr['id'],
          'option_name': opt['option_name'],
          'price_adjustment': opt['price_adjustment'],
          'sort_order': opt['sort_order'],
          'discount_type': opt['discount_type'],
          'discount_value': opt['discount_value'],
        });
      }
    }

    if (mounted) {
      setState(() {
        _pendingEditId = proposalId;
        _liveAttrs = liveAttrsList;
      });
    }
    return proposalId;
  }

  Future<void> _saveContent() async {
    if (_contentSaving) return;
    setState(() {
      _contentSaving = true;
      _contentError = null;
    });
    try {
      final proposalId = await _ensureProposal();
      await _db.from('vendor_service_requests').update({
        'included_items': _includedItems,
        'excluded_items': _excludedItems,
        'before_after_pairs': _beforeAfterPairs,
      }).eq('id', proposalId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _contentSaving = false;
          _contentError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ── Warranty ───────────────────────────────────────────────────────────────

  Future<void> _saveWarranty() async {
    if (_warrantySaving) return;
    if (_warrantyEnabled) {
      final days = int.tryParse(_warrantyDaysCtrl.text.trim());
      if (days == null || days <= 0) {
        setState(() => _warrantyError = 'Enter a valid duration (days > 0).');
        return;
      }
    }
    setState(() {
      _warrantySaving = true;
      _warrantyError = null;
    });
    try {
      final proposalId = await _ensureProposal();
      await _db.from('vendor_service_requests').update({
        'warranty_enabled': _warrantyEnabled,
        'warranty_days': _warrantyEnabled
            ? int.tryParse(_warrantyDaysCtrl.text.trim())
            : null,
        'warranty_covers': _warrantyEnabled && _warrantyCoversCtrl.text.trim().isNotEmpty
            ? _warrantyCoversCtrl.text.trim()
            : null,
        'warranty_exclusions':
            _warrantyEnabled && _warrantyExclusionsCtrl.text.trim().isNotEmpty
                ? _warrantyExclusionsCtrl.text.trim()
                : null,
      }).eq('id', proposalId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _warrantySaving = false;
          _warrantyError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ── Attributes ─────────────────────────────────────────────────────────────

  Future<void> _loadAttrs() async {
    try {
      const attrSelect = '*, service_attribute_options(id, attribute_id, '
          'option_name, price_adjustment, sort_order, discount_type, discount_value)';

      final data = await _db
          .from('service_attributes')
          .select(attrSelect)
          .eq('custom_service_id', _pendingEditId ?? widget.serviceId)
          .order('name', ascending: true);

      // Load live attrs for diff detection when a proposal exists and we
      // haven't already set _liveAttrs (e.g. from _loadContent or _ensureProposal).
      List<_Attr>? newLiveAttrs;
      if (_pendingEditId != null && _liveAttrs == null) {
        final liveData = await _db
            .from('service_attributes')
            .select(attrSelect)
            .eq('custom_service_id', widget.serviceId)
            .order('name', ascending: true);
        newLiveAttrs = (liveData as List)
            .map((e) => _Attr.fromMap(e as Map<String, dynamic>))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _attrs = (data as List)
            .map((e) => _Attr.fromMap(e as Map<String, dynamic>))
            .toList();
        if (newLiveAttrs != null) _liveAttrs = newLiveAttrs;
        _attrsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _attrsLoading = false);
    }
  }

  Future<void> _createAttr({
    required String name,
    required double price,
    required String discountType,
    required double discountValue,
  }) async {
    final proposalId = await _ensureProposal();
    final attrData = await _db
        .from('service_attributes')
        .insert({
          'custom_service_id': proposalId,
          'name': name,
          'field_type': 'dropdown',
          'is_required': false,
        })
        .select()
        .single();
    await _db.from('service_attribute_options').insert({
      'attribute_id': attrData['id'],
      'option_name': name,
      'price_adjustment': price,
      'sort_order': 0,
      'discount_type': discountType,
      'discount_value': discountValue,
    });
    await _loadAttrs();
  }

  Future<void> _editAttr(
    _Attr attr, {
    required String name,
    required double price,
    required String discountType,
    required double discountValue,
  }) async {
    await _db
        .from('service_attributes')
        .update({'name': name})
        .eq('id', attr.id);
    if (attr.options.isNotEmpty) {
      await _db.from('service_attribute_options').update({
        'option_name': name,
        'price_adjustment': price,
        'discount_type': discountType,
        'discount_value': discountValue,
      }).eq('id', attr.options.first.id);
    } else {
      await _db.from('service_attribute_options').insert({
        'attribute_id': attr.id,
        'option_name': name,
        'price_adjustment': price,
        'sort_order': 0,
        'discount_type': discountType,
        'discount_value': discountValue,
      });
    }
    await _loadAttrs();
  }

  Future<void> _deleteAttr(_Attr attr) async {
    await _db
        .from('service_attribute_options')
        .delete()
        .eq('attribute_id', attr.id);
    await _db.from('service_attributes').delete().eq('id', attr.id);
    await _loadAttrs();
  }

  void _openCreateAttr() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AttrFormDialog(
        serviceName: widget.serviceName,
        onSave: ({
          required name,
          required price,
          required discountType,
          required discountValue,
        }) =>
            _createAttr(
          name: name,
          price: price,
          discountType: discountType,
          discountValue: discountValue,
        ),
      ),
    );
  }

  void _openEditAttr(_Attr attr) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AttrFormDialog(
        existing: attr,
        serviceName: widget.serviceName,
        onSave: ({
          required name,
          required price,
          required discountType,
          required discountValue,
        }) =>
            _editAttr(
          attr,
          name: name,
          price: price,
          discountType: discountType,
          discountValue: discountValue,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAttr(_Attr attr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Entry'),
        content: Text('Delete "${attr.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _deleteAttr(attr);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry deleted.')));
    }
  }

  // ── Per-tab diff detection ─────────────────────────────────────────────────

  bool get _contentHasPendingDiff {
    if (_pendingEditId == null || _liveIncluded == null) return false;
    return !_strListEq(_includedItems, _liveIncluded!) ||
        !_strListEq(_excludedItems, _liveExcluded!) ||
        !_mapListEq(_beforeAfterPairs, _liveBeforeAfter!);
  }

  bool get _warrantyHasPendingDiff {
    if (_pendingEditId == null || _liveWarrantyEnabled == null) return false;
    if (_warrantyEnabled != _liveWarrantyEnabled) return true;
    if (!_warrantyEnabled) return false;
    String? norm(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();
    return int.tryParse(_warrantyDaysCtrl.text.trim()) != _liveWarrantyDays ||
        norm(_warrantyCoversCtrl.text) != norm(_liveWarrantyCovers) ||
        norm(_warrantyExclusionsCtrl.text) != norm(_liveWarrantyExclusions);
  }

  bool get _attrsHasPendingDiff {
    if (_pendingEditId == null || _liveAttrs == null) return false;
    return !_attrsListEq(_attrs, _liveAttrs!);
  }

  static bool _strListEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapListEq(
      List<Map<String, String>> a, List<Map<String, String>> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ma = a[i], mb = b[i];
      if (ma.length != mb.length) return false;
      for (final k in ma.keys) {
        if (ma[k] != mb[k]) return false;
      }
    }
    return true;
  }

  static bool _attrsListEq(List<_Attr> a, List<_Attr> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort((x, y) => x.name.compareTo(y.name));
    final sb = [...b]..sort((x, y) => x.name.compareTo(y.name));
    for (int i = 0; i < sa.length; i++) {
      if (sa[i].name != sb[i].name) return false;
      final oa = sa[i].options, ob = sb[i].options;
      if (oa.length != ob.length) return false;
      for (int j = 0; j < oa.length; j++) {
        if (oa[j].optionName != ob[j].optionName) return false;
        if (oa[j].priceAdjustment != ob[j].priceAdjustment) return false;
        if (oa[j].discountType != ob[j].discountType) return false;
        if (oa[j].discountValue != ob[j].discountValue) return false;
      }
    }
    return true;
  }

  // ── Pending banner ─────────────────────────────────────────────────────────

  Widget _pendingBanner(bool show) {
    if (!show) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBE6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD666)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pending_outlined,
              size: 15, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Changes pending admin approval. Customers see the current live version until approved.',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Service Config',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        Text(
                          widget.serviceName,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab bar
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Content'),
                Tab(text: 'Warranty'),
                Tab(text: 'Attributes / Variants'),
              ],
            ),

            // Tab views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildContentTab(),
                  _buildWarrantyTab(),
                  _buildAttributesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentTab() {
    if (_contentLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_contentHasPendingDiff) ...[
            _pendingBanner(true),
            const SizedBox(height: 16),
          ],
          _SectionHeader(
            icon: Icons.check_circle_outline_rounded,
            label: "What's Included",
            color: AppColors.success,
          ),
          const SizedBox(height: 10),
          _EditableItemList(
            items: _includedItems,
            onChanged: (v) => setState(() => _includedItems = v),
            addLabel: 'Add included item',
          ),
          const SizedBox(height: 24),
          const Divider(color: AppColors.border),
          const SizedBox(height: 20),

          _SectionHeader(
            icon: Icons.cancel_outlined,
            label: "What's Excluded",
            color: AppColors.error,
          ),
          const SizedBox(height: 10),
          _EditableItemList(
            items: _excludedItems,
            onChanged: (v) => setState(() => _excludedItems = v),
            addLabel: 'Add excluded item',
          ),
          const SizedBox(height: 24),
          const Divider(color: AppColors.border),
          const SizedBox(height: 20),

          _SectionHeader(
            icon: Icons.compare_rounded,
            label: 'Before & After',
            color: AppColors.accent,
          ),
          const SizedBox(height: 10),
          _BeforeAfterEditor(
            pairs: _beforeAfterPairs,
            serviceId: widget.serviceId,
            onChanged: (v) => setState(() => _beforeAfterPairs = v),
          ),
          const SizedBox(height: 28),

          if (_contentError != null) ...[
            Text(_contentError!,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _contentSaving ? null : _saveContent,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size.fromHeight(44),
              ),
              child: _contentSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Content',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyTab() {
    if (_contentLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    InputDecoration inputDeco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppColors.border, width: 0.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppColors.border, width: 0.8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_warrantyHasPendingDiff) ...[
            _pendingBanner(true),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            value: _warrantyEnabled,
            onChanged: (v) => setState(() {
              _warrantyEnabled = v;
              if (!v) {
                _warrantyDaysCtrl.clear();
                _warrantyCoversCtrl.clear();
                _warrantyExclusionsCtrl.clear();
              }
            }),
            title: const Text(
              'Warranty Coverage',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Offer a warranty on this service',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            activeThumbColor: AppColors.success,
            contentPadding: EdgeInsets.zero,
          ),
          if (_warrantyEnabled) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _warrantyDaysCtrl,
              keyboardType: TextInputType.number,
              decoration: inputDeco('Duration (Days) *'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _warrantyCoversCtrl,
              maxLines: 4,
              decoration: inputDeco('Warranty Covers').copyWith(
                hintText: 'One item per line…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _warrantyExclusionsCtrl,
              maxLines: 4,
              decoration: inputDeco('Warranty Does Not Cover').copyWith(
                hintText: 'One item per line…',
                alignLabelWithHint: true,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_warrantyError != null) ...[
            Text(_warrantyError!,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _warrantySaving ? null : _saveWarranty,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size.fromHeight(44),
              ),
              child: _warrantySaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Warranty',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributesTab() {
    if (_attrsLoading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_attrsHasPendingDiff) _pendingBanner(true),
        Padding(
          padding: EdgeInsets.fromLTRB(20, _attrsHasPendingDiff ? 12 : 16, 20, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openCreateAttr,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Entry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        Expanded(
          child: _attrs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_outlined,
                          size: 40, color: AppColors.textSecondary),
                      SizedBox(height: 12),
                      Text('No entries yet.',
                          style: TextStyle(color: AppColors.textSecondary)),
                      SizedBox(height: 4),
                      Text('e.g. "1 AC – ₹800", "2 ACs – ₹1500"',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textHint)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: _attrs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _AttributeRow(
                    attr: _attrs[i],
                    onEdit: () => _openEditAttr(_attrs[i]),
                    onDelete: () => _confirmDeleteAttr(_attrs[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section header
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Editable text list
// ═══════════════════════════════════════════════════════════════════════════════

class _EditableItemList extends StatefulWidget {
  const _EditableItemList({
    required this.items,
    required this.onChanged,
    required this.addLabel,
  });
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;

  @override
  State<_EditableItemList> createState() => _EditableItemListState();
}

class _EditableItemListState extends State<_EditableItemList> {
  late List<String> _items;
  bool _adding = false;
  final _addCtrl = TextEditingController();
  int? _editingIndex;
  final _editCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  @override
  void didUpdateWidget(_EditableItemList old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items) _items = List.from(widget.items);
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _addCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _items.add(text);
        _addCtrl.clear();
        _adding = false;
      });
      widget.onChanged(List.from(_items));
    } else {
      setState(() => _adding = false);
    }
  }

  void _startEdit(int i) {
    setState(() {
      _editingIndex = i;
      _editCtrl.text = _items[i];
    });
  }

  void _commitEdit(int i) {
    final text = _editCtrl.text.trim();
    if (text.isNotEmpty && text != _items[i]) {
      setState(() => _items[i] = text);
      widget.onChanged(List.from(_items));
    }
    setState(() => _editingIndex = null);
  }

  void _delete(int i) {
    setState(() => _items.removeAt(i));
    widget.onChanged(List.from(_items));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_items.isEmpty && !_adding)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No items yet.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        if (_items.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorder: (oldIdx, newIdx) {
              if (newIdx > oldIdx) newIdx--;
              setState(() {
                final item = _items.removeAt(oldIdx);
                _items.insert(newIdx, item);
                if (_editingIndex == oldIdx) _editingIndex = newIdx;
              });
              widget.onChanged(List.from(_items));
            },
            proxyDecorator: (child, _, _) => Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                child: child),
            itemBuilder: (_, i) {
              final isEditing = _editingIndex == i;
              return Container(
                key: ValueKey('item_$i'),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.drag_handle_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: isEditing
                          ? TextField(
                              controller: _editCtrl,
                              autofocus: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 6)),
                              onSubmitted: (_) => _commitEdit(i),
                            )
                          : GestureDetector(
                              onDoubleTap: () => _startEdit(i),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Text(_items[i],
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                    ),
                    if (isEditing)
                      IconButton(
                        icon: const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.success),
                        onPressed: () => _commitEdit(i),
                        tooltip: 'Save',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 14, color: AppColors.textSecondary),
                        onPressed: () => _startEdit(i),
                        tooltip: 'Edit',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 14, color: AppColors.error),
                      onPressed: () => _delete(i),
                      tooltip: 'Remove',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            },
          ),
        if (_adding)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.accent),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Enter item…',
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                TextButton(
                  onPressed: _commit,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text('Add', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _adding = false;
                    _addCtrl.clear();
                  }),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _adding = true),
          icon: const Icon(Icons.add_rounded, size: 14),
          label: Text(widget.addLabel, style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Before & After image pair editor
// ═══════════════════════════════════════════════════════════════════════════════

class _BeforeAfterEditor extends StatefulWidget {
  const _BeforeAfterEditor({
    required this.pairs,
    required this.serviceId,
    required this.onChanged,
  });
  final List<Map<String, String>> pairs;
  final String serviceId;
  final ValueChanged<List<Map<String, String>>> onChanged;

  @override
  State<_BeforeAfterEditor> createState() => _BeforeAfterEditorState();
}

class _BeforeAfterEditorState extends State<_BeforeAfterEditor> {
  late List<Map<String, String>> _pairs;

  @override
  void initState() {
    super.initState();
    _pairs = widget.pairs.map((p) => Map<String, String>.from(p)).toList();
  }

  @override
  void didUpdateWidget(_BeforeAfterEditor old) {
    super.didUpdateWidget(old);
    if (old.pairs != widget.pairs) {
      _pairs =
          widget.pairs.map((p) => Map<String, String>.from(p)).toList();
    }
  }

  void _addPair() {
    setState(() => _pairs.add({'before_url': '', 'after_url': ''}));
    widget.onChanged(List.from(_pairs));
  }

  void _deletePair(int i) {
    setState(() => _pairs.removeAt(i));
    widget.onChanged(List.from(_pairs));
  }

  void _setUrl(int i, String key, String url) {
    setState(() => _pairs[i] = Map.from(_pairs[i])..[key] = url);
    widget.onChanged(List.from(_pairs));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pairs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No pairs yet.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _pairs.length,
          onReorder: (oldIdx, newIdx) {
            if (newIdx > oldIdx) newIdx--;
            setState(() {
              final pair = _pairs.removeAt(oldIdx);
              _pairs.insert(newIdx, pair);
            });
            widget.onChanged(List.from(_pairs));
          },
          proxyDecorator: (child, _, _) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: child),
          itemBuilder: (_, i) {
            final pair = _pairs[i];
            return Container(
              key: ValueKey('pair_$i'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pair ${i + 1}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.error),
                        onPressed: () => _deletePair(i),
                        tooltip: 'Remove pair',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ImageUploadField(
                          label: 'Before',
                          url: pair['before_url'] ?? '',
                          serviceId: widget.serviceId,
                          onChanged: (url) => _setUrl(i, 'before_url', url),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ImageUploadField(
                          label: 'After',
                          url: pair['after_url'] ?? '',
                          serviceId: widget.serviceId,
                          onChanged: (url) => _setUrl(i, 'after_url', url),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        TextButton.icon(
          onPressed: _addPair,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 14),
          label: const Text('Add Before/After Pair',
              style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Image upload field
// ═══════════════════════════════════════════════════════════════════════════════

const _kVendorContentBucket = 'vendor-requests';

class _ImageUploadField extends StatefulWidget {
  const _ImageUploadField({
    required this.label,
    required this.url,
    required this.serviceId,
    required this.onChanged,
  });
  final String label;
  final String url;
  final String serviceId;
  final ValueChanged<String> onChanged;

  @override
  State<_ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<_ImageUploadField> {
  bool _uploading = false;

  Future<void> _pick() async {
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
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path =
        '${widget.serviceId}/content/$ts.${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    setState(() => _uploading = true);
    try {
      final mime = const {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
          }[ext] ??
          'image/jpeg';
      await Supabase.instance.client.storage
          .from(_kVendorContentBucket)
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: mime, upsert: true));
      final url = Supabase.instance.client.storage
          .from(_kVendorContentBucket)
          .getPublicUrl(path);
      if (mounted) {
        setState(() => _uploading = false);
        widget.onChanged(url);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (hasImage)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  widget.url,
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.textSecondary),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => widget.onChanged(''),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _uploading ? null : _pick,
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.edit_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: _uploading ? null : _pick,
            child: Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: _uploading
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent)))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_rounded,
                            size: 20, color: AppColors.textSecondary),
                        SizedBox(height: 4),
                        Text('Upload',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Attribute row
// ═══════════════════════════════════════════════════════════════════════════════

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({
    required this.attr,
    required this.onEdit,
    required this.onDelete,
  });
  final _Attr attr;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final price =
        attr.options.isNotEmpty ? attr.options.first.priceAdjustment : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attr.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (price > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '₹${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 15),
            tooltip: 'Edit entry',
            color: AppColors.textSecondary,
            onPressed: onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 15),
            tooltip: 'Delete entry',
            color: AppColors.error,
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Attribute form dialog (Add / Edit entry)
// ═══════════════════════════════════════════════════════════════════════════════

class _AttrFormDialog extends StatefulWidget {
  const _AttrFormDialog({
    this.existing,
    required this.serviceName,
    required this.onSave,
  });
  final _Attr? existing;
  final String serviceName;
  final Future<void> Function({
    required String name,
    required double price,
    required String discountType,
    required double discountValue,
  }) onSave;

  @override
  State<_AttrFormDialog> createState() => _AttrFormDialogState();
}

class _AttrFormDialogState extends State<_AttrFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _discountValue;
  String _discountType = 'percentage';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    final firstOpt = e?.options.isNotEmpty == true ? e!.options.first : null;
    _price = TextEditingController(
        text: (firstOpt?.priceAdjustment ?? 0) == 0
            ? ''
            : firstOpt!.priceAdjustment.toStringAsFixed(0));
    _discountType = firstOpt?.discountType ?? 'percentage';
    _discountValue = TextEditingController(
        text: (firstOpt?.discountValue ?? 0) > 0
            ? firstOpt!.discountValue.toStringAsFixed(0)
            : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        name: _name.text.trim(),
        price: double.tryParse(_price.text.trim()) ?? 0.0,
        discountType: _discountType,
        discountValue: double.tryParse(_discountValue.text.trim()) ?? 0.0,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEdit
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Entry' : 'Add Entry',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Form
            Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service label
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primary
                                .withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                              Icons.miscellaneous_services_rounded,
                              size: 16,
                              color: AppColors.primary),
                          const SizedBox(width: 8),
                          const Text('Service:',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.serviceName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.lock_outline,
                              size: 13,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _name,
                      decoration: _inputDeco('e.g. 2 ACs').copyWith(
                          labelText: 'Name *'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: _inputDeco('e.g. 2000').copyWith(
                        labelText: 'Price (₹) *',
                        prefixText: '₹ ',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Discount
                    const Text(
                      'DISCOUNT (OPTIONAL)',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 44,
                          child: ToggleButtons(
                          isSelected: [
                            _discountType == 'percentage',
                            _discountType == 'flat',
                          ],
                          onPressed: (i) => setState(() =>
                              _discountType =
                                  i == 0 ? 'percentage' : 'flat'),
                          borderRadius: BorderRadius.circular(8),
                          selectedColor: Colors.white,
                          fillColor: AppColors.primary,
                          textStyle: const TextStyle(fontSize: 13),
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 44, maxHeight: 44),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('%'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('₹'),
                            ),
                          ],
                        ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextFormField(
                              controller: _discountValue,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              decoration: _inputDeco(
                                _discountType == 'percentage'
                                    ? 'Discount %'
                                    : 'Discount ₹',
                              ).copyWith(
                                prefixText: _discountType == 'percentage'
                                    ? null
                                    : '₹ ',
                                suffixText: _discountType == 'percentage'
                                    ? '%'
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 125,
                    height: 44,
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.zero,
                        fixedSize: const Size(125, 44),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 125,
                    height: 44,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.zero,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Save Changes' : 'Add Entry'),
                    ),
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
