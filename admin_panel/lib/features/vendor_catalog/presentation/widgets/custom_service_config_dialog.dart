import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../catalog_configs/data/catalog_node_configs_repository.dart';
import '../../../catalog_configs/domain/models/catalog_node_config_model.dart';
import '../../../vendor_subscriptions/domain/models/subscription_plan.dart'
    show kBillingCycles;

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// CustomServiceConfigDialog â€” 7-tab module configuration for a vendor custom
// service (vendor_service_requests row).
//
// Tabs: Tax Â· Loyalty Â· Scheduling Â· Platform Commission Â· Surge Fee Â·
//       Preferred Vendors Â· Vendor Subscription
//
// Module configs are stored in catalog_node_configs.custom_service_id.
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class CustomServiceConfigDialog extends StatefulWidget {
  final String customServiceId;
  final String serviceName;

  const CustomServiceConfigDialog({
    super.key,
    required this.customServiceId,
    required this.serviceName,
  });

  static Future<void> show(
    BuildContext context, {
    required String customServiceId,
    required String serviceName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomServiceConfigDialog(
        customServiceId: customServiceId,
        serviceName: serviceName,
      ),
    );
  }

  @override
  State<CustomServiceConfigDialog> createState() =>
      _CustomServiceConfigDialogState();
}

class _CustomServiceConfigDialogState extends State<CustomServiceConfigDialog>
    with SingleTickerProviderStateMixin {
  final _repo = CatalogNodeConfigsRepository(Supabase.instance.client);

  late TabController _tabController;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Configs keyed by module
  final Map<String, CatalogNodeConfigModel?> _configs = {};

  // â”€â”€ Tax â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _taxValueCtrl = TextEditingController();
  String _taxType = 'percentage';
  final _taxNameCtrl = TextEditingController(text: 'GST');

  // â”€â”€ Loyalty â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _loyaltyEarnEnabled = true;
  String _loyaltyRule = 'global';
  final _loyaltyFixedCtrl = TextEditingController();
  final _loyaltyPercentCtrl = TextEditingController();

  // â”€â”€ Scheduling â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _schedEnabled = true;
  final List<bool> _schedDays = List.filled(7, true);
  final _schedMaxCtrl = TextEditingController(text: '5');
  final _schedSlotsCtrl = TextEditingController();

  // â”€â”€ Commission â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _commValueCtrl = TextEditingController();
  String _commType = 'percentage';

  // â”€â”€ Surge fee â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _surgeValueCtrl = TextEditingController();
  String _surgeType = 'percentage';
  final _surgeNameCtrl = TextEditingController(text: 'Surge Fee');

  // â”€â”€ Preferred vendors â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _pvEnabled = false;
  Set<String> _pvSelectedIds = {};
  Map<String, double> _pvVendorFees = {};
  final Map<String, TextEditingController> _pvFeeControllers = {};
  List<Map<String, dynamic>> _pvVendors = [];

  // â”€â”€ Vendor Subscription â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _vsEnabled = false;
  final _vsNameCtrl = TextEditingController();
  final _vsDescCtrl = TextEditingController();
  String _vsBillingCycle = 'monthly';
  final _vsDurationCtrl = TextEditingController(text: '30');
  final _vsJoiningFeeCtrl = TextEditingController();
  final _vsSubFeeCtrl = TextEditingController();
  final _vsCommissionPctCtrl = TextEditingController();
  bool _vsIsActive = true;
  bool _vsAllowCod = false;
  bool _vsAllowAssignment = false;
  bool _vsPriorityListing = false;

  // Global master-switch states (null = still loading)
  bool? _globalTaxEnabled;
  bool? _globalLoyaltyEnabled;
  bool? _globalSurgeEnabled;

  static const _modules = [
    'tax', 'loyalty', 'scheduling', 'commission',
    'surge', 'preferred_vendors', 'vendor_subscription',
  ];
  static const _tabLabels = [
    'Tax', 'Loyalty', 'Scheduling', 'Platform Commission',
    'Surge Fee', 'Preferred Vendors', 'Vendor Subscription',
  ];
  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _taxValueCtrl.dispose();
    _taxNameCtrl.dispose();
    _loyaltyFixedCtrl.dispose();
    _loyaltyPercentCtrl.dispose();
    _schedMaxCtrl.dispose();
    _schedSlotsCtrl.dispose();
    _commValueCtrl.dispose();
    _surgeValueCtrl.dispose();
    _surgeNameCtrl.dispose();
    for (final ctrl in _pvFeeControllers.values) {
      ctrl.dispose();
    }
    _vsNameCtrl.dispose();
    _vsDescCtrl.dispose();
    _vsDurationCtrl.dispose();
    _vsJoiningFeeCtrl.dispose();
    _vsSubFeeCtrl.dispose();
    _vsCommissionPctCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Data loading â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadData() async {
    try {
      final cfgRows =
          await _repo.fetchForCustomService(widget.customServiceId);
      for (final m in _modules) {
        _configs[m] = cfgRows.where((c) => c.module == m).firstOrNull;
      }

      if (_pvVendors.isEmpty) {
        final rows = await Supabase.instance.client
            .from('vendors')
            .select('id, business_name, preferred_vendor_fee, rating')
            .eq('is_preferred_vendor', true)
            .eq('is_active', true)
            .order('business_name');
        _pvVendors = (rows as List).cast<Map<String, dynamic>>();
      }

      try {
        final taxRow = await Supabase.instance.client
            .from('tax_settings')
            .select('is_enabled')
            .limit(1)
            .maybeSingle();
        _globalTaxEnabled = (taxRow?['is_enabled'] as bool?) ?? true;

        final loyaltyRow = await Supabase.instance.client
            .from('loyalty_settings')
            .select('is_enabled')
            .limit(1)
            .maybeSingle();
        _globalLoyaltyEnabled = (loyaltyRow?['is_enabled'] as bool?) ?? true;

        final surgeRow = await Supabase.instance.client
            .from('surge_fee_settings')
            .select('is_enabled')
            .limit(1)
            .maybeSingle();
        _globalSurgeEnabled = (surgeRow?['is_enabled'] as bool?) ?? false;
      } catch (_) {
        _globalTaxEnabled ??= true;
        _globalLoyaltyEnabled ??= true;
        _globalSurgeEnabled ??= false;
      }

      _populateAll();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _refreshConfigs() async {
    final cfgRows = await _repo.fetchForCustomService(widget.customServiceId);
    for (final m in _modules) {
      _configs[m] = cfgRows.where((c) => c.module == m).firstOrNull;
    }
    _populateAll();
    if (mounted) setState(() {});
  }

  void _populateAll() {
    _populateTax();
    _populateLoyalty();
    _populateScheduling();
    _populateCommission();
    _populateSurge();
    _populatePreferredVendors();
    _populateVendorSubscription();
  }

  void _populateTax() {
    final cfg = _configs['tax'];
    if (cfg != null) {
      _taxNameCtrl.text = cfg.config['tax_name'] as String? ?? 'GST';
      _taxType = cfg.config['tax_type'] as String? ?? 'percentage';
      _taxValueCtrl.text = (cfg.config['tax_value'] as num?)?.toString() ?? '';
    }
  }

  void _populateLoyalty() {
    final cfg = _configs['loyalty'];
    if (cfg != null) {
      _loyaltyEarnEnabled = cfg.config['earn_enabled'] as bool? ?? true;
      _loyaltyRule = cfg.config['earn_rule'] as String? ?? 'global';
      _loyaltyFixedCtrl.text =
          (cfg.config['fixed_points'] as num?)?.toString() ?? '';
      _loyaltyPercentCtrl.text =
          (cfg.config['earn_per_100'] as num?)?.toString() ?? '';
    }
  }

  void _populateScheduling() {
    final cfg = _configs['scheduling'];
    if (cfg != null) {
      _schedEnabled = cfg.config['is_enabled'] as bool? ?? true;
      final days = (cfg.config['working_days'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          {};
      for (int i = 0; i < 7; i++) {
        _schedDays[i] = days.contains(i);
      }
      _schedMaxCtrl.text =
          (cfg.config['max_bookings_per_slot'] as num?)?.toString() ?? '5';
      final slots =
          (cfg.config['slots'] as List<dynamic>?)?.cast<String>() ?? [];
      _schedSlotsCtrl.text = slots.join(', ');
    }
  }

  void _populateCommission() {
    final cfg = _configs['commission'];
    if (cfg != null) {
      _commType = cfg.config['commission_type'] as String? ?? 'percentage';
      _commValueCtrl.text =
          (cfg.config['commission_value'] as num?)?.toString() ?? '';
    }
  }

  void _populateSurge() {
    final cfg = _configs['surge'];
    if (cfg != null) {
      _surgeNameCtrl.text = cfg.config['surge_name'] as String? ?? 'Surge Fee';
      _surgeType = cfg.config['surge_type'] as String? ?? 'percentage';
      _surgeValueCtrl.text =
          (cfg.config['surge_value'] as num?)?.toString() ?? '';
    }
  }

  void _populatePreferredVendors() {
    final cfg = _configs['preferred_vendors'];
    if (cfg != null) {
      _pvEnabled = cfg.config['is_enabled'] as bool? ?? false;
      final vendorsArr = cfg.config['vendors'] as List<dynamic>?;
      if (vendorsArr != null) {
        _pvSelectedIds =
            vendorsArr.map((e) => (e as Map)['id'] as String).toSet();
        _pvVendorFees = {
          for (final e in vendorsArr.cast<Map<String, dynamic>>())
            e['id'] as String: (e['fee'] as num?)?.toDouble() ?? 0.0,
        };
      } else {
        _pvSelectedIds = (cfg.config['vendor_ids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ??
            {};
        _pvVendorFees = {
          for (final id in _pvSelectedIds)
            id: (_pvVendors
                        .where((v) => v['id'] == id)
                        .firstOrNull?['preferred_vendor_fee'] as num?)
                    ?.toDouble() ??
                0.0,
        };
      }
    } else {
      _pvEnabled = false;
      _pvSelectedIds = {};
      _pvVendorFees = {};
    }
    _syncPvFeeControllers();
  }

  void _syncPvFeeControllers() {
    for (final id in _pvSelectedIds) {
      final fee = _pvVendorFees[id] ?? 0.0;
      final existing = _pvFeeControllers[id];
      if (existing != null) {
        existing.text = fee.toStringAsFixed(0);
      } else {
        _pvFeeControllers[id] =
            TextEditingController(text: fee.toStringAsFixed(0));
      }
    }
  }

  void _populateVendorSubscription() {
    final cfg = _configs['vendor_subscription'];
    if (cfg != null) {
      _vsEnabled = cfg.config['is_enabled'] as bool? ?? false;
      _vsNameCtrl.text = cfg.config['name'] as String? ?? '';
      _vsDescCtrl.text = cfg.config['description'] as String? ?? '';
      _vsBillingCycle = cfg.config['billing_cycle'] as String? ?? 'monthly';
      _vsDurationCtrl.text =
          (cfg.config['duration_days'] as num?)?.toString() ?? '30';
      final jf = cfg.config['joining_fee'];
      _vsJoiningFeeCtrl.text =
          jf != null ? (jf as num).toStringAsFixed(2) : '';
      final sf = cfg.config['subscription_fee'];
      _vsSubFeeCtrl.text =
          sf != null ? (sf as num).toStringAsFixed(2) : '';
      _vsIsActive = cfg.config['is_active'] as bool? ?? true;
      final perms =
          (cfg.config['permissions'] as Map?)?.cast<String, dynamic>() ?? {};
      _vsAllowCod = perms['allow_cod'] == true;
      _vsAllowAssignment = perms['allow_booking_assignment'] == true;
      _vsPriorityListing = perms['priority_listing'] == true;
      final commPct = perms['reduced_commission_pct'];
      _vsCommissionPctCtrl.text =
          commPct != null ? (commPct as num).toStringAsFixed(0) : '';
    }
  }

  // â”€â”€ Save / Delete (module configs) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _save(String module) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = _buildConfig(module);
      final existing = _configs[module];

      final model = CatalogNodeConfigModel(
        id: existing?.id ?? '',
        module: module,
        customServiceId: widget.customServiceId,
        config: config,
        isEnabled: true,
      );

      await _repo.upsertForCustomService(model);
      await _refreshConfigs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_tabLabels[_modules.indexOf(module)]} settings saved.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String module) async {
    final existing = _configs[module];
    if (existing == null) return;
    setState(() => _saving = true);
    try {
      await _repo.deleteById(existing.id);
      await _refreshConfigs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_tabLabels[_modules.indexOf(module)]} settings removed â€” default settings will apply.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _buildConfig(String module) {
    switch (module) {
      case 'tax':
        return {
          'tax_name': _taxNameCtrl.text.trim().isEmpty
              ? 'GST'
              : _taxNameCtrl.text.trim(),
          'tax_type': _taxType,
          'tax_value': double.tryParse(_taxValueCtrl.text.trim()) ?? 0.0,
        };
      case 'loyalty':
        return {
          'earn_enabled': _loyaltyEarnEnabled,
          'earn_rule': _loyaltyRule,
          'fixed_points': int.tryParse(_loyaltyFixedCtrl.text.trim()),
          'earn_per_100': int.tryParse(_loyaltyPercentCtrl.text.trim()),
        };
      case 'scheduling':
        final days = <int>[];
        for (int i = 0; i < 7; i++) {
          if (_schedDays[i]) days.add(i);
        }
        final rawSlots = _schedSlotsCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        return {
          'is_enabled': _schedEnabled,
          'working_days': days,
          'max_bookings_per_slot':
              int.tryParse(_schedMaxCtrl.text.trim()) ?? 5,
          'slots': rawSlots,
        };
      case 'commission':
        return {
          'commission_type': _commType,
          'commission_value':
              double.tryParse(_commValueCtrl.text.trim()) ?? 0.0,
        };
      case 'surge':
        return {
          'surge_name': _surgeNameCtrl.text.trim().isEmpty
              ? 'Surge Fee'
              : _surgeNameCtrl.text.trim(),
          'surge_type': _surgeType,
          'surge_value': double.tryParse(_surgeValueCtrl.text.trim()) ?? 0.0,
        };
      case 'preferred_vendors':
        for (final id in _pvSelectedIds) {
          final ctrl = _pvFeeControllers[id];
          if (ctrl != null) {
            _pvVendorFees[id] = double.tryParse(ctrl.text.trim()) ?? 0.0;
          }
        }
        return {
          'is_enabled': _pvEnabled,
          'vendors': _pvSelectedIds
              .map((id) => {'id': id, 'fee': _pvVendorFees[id] ?? 0.0})
              .toList(),
        };
      case 'vendor_subscription':
        final perms = <String, dynamic>{
          'allow_cod': _vsAllowCod,
          'allow_booking_assignment': _vsAllowAssignment,
          'priority_listing': _vsPriorityListing,
          if (_vsCommissionPctCtrl.text.trim().isNotEmpty)
            'reduced_commission_pct':
                double.tryParse(_vsCommissionPctCtrl.text.trim()) ?? 0.0,
        };
        return {
          'is_enabled': _vsEnabled,
          'name': _vsNameCtrl.text.trim(),
          'description': _vsDescCtrl.text.trim().isEmpty
              ? null
              : _vsDescCtrl.text.trim(),
          'billing_cycle': _vsBillingCycle,
          'duration_days': int.tryParse(_vsDurationCtrl.text.trim()) ?? 30,
          'joining_fee': _vsJoiningFeeCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(_vsJoiningFeeCtrl.text.trim()),
          'subscription_fee': _vsSubFeeCtrl.text.trim().isEmpty
              ? null
              : double.tryParse(_vsSubFeeCtrl.text.trim()),
          'is_active': _vsIsActive,
          'permissions': perms,
        };
      default:
        return {};
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Module Configuration',
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

            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else ...[
              // â”€â”€ Tabs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12)),
                ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _modules.map(_buildModuleTab).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _moduleGloballyEnabled(String module) {
    switch (module) {
      case 'tax':
        return _globalTaxEnabled ?? true;
      case 'loyalty':
        return _globalLoyaltyEnabled ?? true;
      case 'surge':
        return _globalSurgeEnabled ?? false;
      default:
        return true;
    }
  }

  Widget _buildModuleTab(String module) {
    final existing = _configs[module];
    final globallyEnabled = _moduleGloballyEnabled(module);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!globallyEnabled) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCA28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFF57F17), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_tabLabels[_modules.indexOf(module)]} is globally disabled',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5D4037),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'These settings are saved but won\'t take effect until this module is enabled in Global Settings.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF795548)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildModuleFields(module),

          const SizedBox(height: 20),

          Row(
            children: [
              if (existing != null) ...[
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _delete(module),
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Remove settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
                const Spacer(),
              ] else
                const Spacer(),
              FilledButton(
                onPressed: _saving ? null : () => _save(module),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),

          if (existing == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No custom settings â€” default ${_tabLabels[_modules.indexOf(module)]} settings will apply.',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModuleFields(String module) {
    switch (module) {
      case 'tax':
        return _buildTaxFields();
      case 'loyalty':
        return _buildLoyaltyFields();
      case 'scheduling':
        return _buildSchedulingFields();
      case 'commission':
        return _buildCommissionFields();
      case 'surge':
        return _buildSurgeFields();
      case 'preferred_vendors':
        return _buildPreferredVendorsFields();
      case 'vendor_subscription':
        return _buildVendorSubscriptionFields();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTaxFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Tax Name'),
        const SizedBox(height: 4),
        TextField(controller: _taxNameCtrl, decoration: _inputDeco('e.g. GST')),
        const SizedBox(height: 12),
        _label('Tax Type'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'percentage', label: Text('Percentage (%)')),
            ButtonSegment(value: 'fixed', label: Text('Fixed (â‚¹)')),
          ],
          selected: {_taxType},
          onSelectionChanged: (s) => setState(() => _taxType = s.first),
        ),
        const SizedBox(height: 12),
        _label(_taxType == 'percentage' ? 'Tax Rate (%)' : 'Fixed Amount (â‚¹)'),
        const SizedBox(height: 4),
        TextField(
          controller: _taxValueCtrl,
          decoration:
              _inputDeco(_taxType == 'percentage' ? 'e.g. 12' : 'e.g. 50'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      ],
    );
  }

  Widget _buildLoyaltyFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title:
              const Text('Loyalty Earn Enabled', style: TextStyle(fontSize: 13)),
          value: _loyaltyEarnEnabled,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _loyaltyEarnEnabled = v),
        ),
        const SizedBox(height: 8),
        _label('Earn Rule'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: _loyaltyRule,
          decoration: _inputDeco(''),
          items: const [
            DropdownMenuItem(value: 'global', child: Text('Global rate')),
            DropdownMenuItem(value: 'fixed', child: Text('Fixed points')),
            DropdownMenuItem(
                value: 'percentage', child: Text('Points per â‚¹100')),
          ],
          onChanged: (v) => setState(() => _loyaltyRule = v ?? 'global'),
        ),
        if (_loyaltyRule == 'fixed') ...[
          const SizedBox(height: 12),
          _label('Fixed Points'),
          const SizedBox(height: 4),
          TextField(
            controller: _loyaltyFixedCtrl,
            decoration: _inputDeco('e.g. 50'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ] else if (_loyaltyRule == 'percentage') ...[
          const SizedBox(height: 12),
          _label('Points per â‚¹100 spent'),
          const SizedBox(height: 4),
          TextField(
            controller: _loyaltyPercentCtrl,
            decoration: _inputDeco('e.g. 5'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ],
    );
  }

  Widget _buildSchedulingFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Scheduling Enabled', style: TextStyle(fontSize: 13)),
          value: _schedEnabled,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _schedEnabled = v),
        ),
        const SizedBox(height: 8),
        _label('Working Days'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: List.generate(7, (i) {
            return FilterChip(
              label:
                  Text(_dayLabels[i], style: const TextStyle(fontSize: 12)),
              selected: _schedDays[i],
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
              onSelected: (v) => setState(() => _schedDays[i] = v),
            );
          }),
        ),
        const SizedBox(height: 12),
        _label('Max Bookings per Slot'),
        const SizedBox(height: 4),
        TextField(
          controller: _schedMaxCtrl,
          decoration: _inputDeco('e.g. 5'),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        _label('Time Slots (comma-separated, e.g. 09:00 AM, 11:00 AM)'),
        const SizedBox(height: 4),
        TextField(
          controller: _schedSlotsCtrl,
          decoration: _inputDeco('09:00 AM, 11:00 AM, 02:00 PM'),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildCommissionFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Platform Commission Type'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'percentage', label: Text('Percentage (%)')),
            ButtonSegment(value: 'fixed', label: Text('Fixed (â‚¹)')),
          ],
          selected: {_commType},
          onSelectionChanged: (s) => setState(() => _commType = s.first),
        ),
        const SizedBox(height: 12),
        _label(_commType == 'percentage'
            ? 'Platform Commission Rate (%)'
            : 'Fixed Amount (â‚¹)'),
        const SizedBox(height: 4),
        TextField(
          controller: _commValueCtrl,
          decoration:
              _inputDeco(_commType == 'percentage' ? 'e.g. 15' : 'e.g. 100'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      ],
    );
  }

  Widget _buildSurgeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Charge Name'),
        const SizedBox(height: 4),
        TextField(
          controller: _surgeNameCtrl,
          decoration: _inputDeco('e.g. Surge Fee, Peak Hours'),
        ),
        const SizedBox(height: 12),
        _label('Charge Type'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'percentage', label: Text('Percentage (%)')),
            ButtonSegment(value: 'fixed', label: Text('Fixed (â‚¹)')),
          ],
          selected: {_surgeType},
          onSelectionChanged: (s) => setState(() => _surgeType = s.first),
        ),
        const SizedBox(height: 12),
        _label(_surgeType == 'percentage'
            ? 'Surge Rate (%)'
            : 'Fixed Amount (â‚¹)'),
        const SizedBox(height: 4),
        TextField(
          controller: _surgeValueCtrl,
          decoration:
              _inputDeco(_surgeType == 'percentage' ? 'e.g. 10' : 'e.g. 50'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      ],
    );
  }

  Widget _buildPreferredVendorsFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Enable Preferred Vendors',
              style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            'Show a vendor selection section at checkout for this service',
            style: TextStyle(fontSize: 11),
          ),
          value: _pvEnabled,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _pvEnabled = v),
        ),
        if (_pvEnabled) ...[
          const SizedBox(height: 12),
          _label('Available Vendors'),
          const SizedBox(height: 8),
          if (_pvVendors.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'No preferred vendors found. Enable "Preferred Vendor" on '
                'vendor profiles first.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _pvVendors.map((v) {
                final id = v['id'] as String;
                final name = v['business_name'] as String? ?? '';
                final isSelected = _pvSelectedIds.contains(id);
                return FilterChip(
                  label:
                      Text(name, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.primary,
                  onSelected: (val) => setState(() {
                    if (val) {
                      _pvSelectedIds.add(id);
                      if (!_pvFeeControllers.containsKey(id)) {
                        final globalFee =
                            (v['preferred_vendor_fee'] as num?)
                                    ?.toDouble() ??
                                0.0;
                        _pvVendorFees[id] = globalFee;
                        _pvFeeControllers[id] = TextEditingController(
                            text: globalFee.toStringAsFixed(0));
                      }
                    } else {
                      _pvSelectedIds.remove(id);
                    }
                  }),
                );
              }).toList(),
            ),

          if (_pvSelectedIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            _label('Additional Fee per Vendor (â‚¹)'),
            const SizedBox(height: 8),
            ..._pvVendors
                .where((v) => _pvSelectedIds.contains(v['id'] as String))
                .map((v) {
              final id = v['id'] as String;
              final name = v['business_name'] as String? ?? '';
              final ctrl = _pvFeeControllers[id];
              if (ctrl == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: ctrl,
                        decoration:
                            _inputDeco('e.g. 200').copyWith(prefixText: 'â‚¹ '),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (val) =>
                            _pvVendorFees[id] = double.tryParse(val) ?? 0.0,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  Widget _buildVendorSubscriptionFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Enable Vendor Subscription',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'Vendors can purchase a subscription scoped to this service',
            style: TextStyle(fontSize: 11),
          ),
          value: _vsEnabled,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _vsEnabled = v),
        ),
        if (_vsEnabled) ...[
          const SizedBox(height: 14),
          _label('Plan Name'),
          const SizedBox(height: 4),
          TextField(
            controller: _vsNameCtrl,
            decoration: _inputDeco('e.g. AC Service Pro Plan'),
          ),
          const SizedBox(height: 12),
          _label('Description (optional)'),
          const SizedBox(height: 4),
          TextField(
            controller: _vsDescCtrl,
            maxLines: 2,
            decoration: _inputDeco('Brief description for vendors'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Billing Cycle'),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: _vsBillingCycle,
                      decoration: _inputDeco(''),
                      items: kBillingCycles
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                    c[0].toUpperCase() + c.substring(1),
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _vsBillingCycle = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Duration (days)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _vsDurationCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('30'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Joining Fee (optional)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _vsJoiningFeeCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDeco('0.00'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Subscription Fee (optional)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _vsSubFeeCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDeco('0.00'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Permissions',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _vsPermTile(
            'Allow COD',
            'Vendor can accept Cash on Delivery payments',
            _vsAllowCod,
            (v) => setState(() => _vsAllowCod = v),
          ),
          _vsPermTile(
            'Allow Booking Assignment',
            'Admin can manually assign bookings to this vendor',
            _vsAllowAssignment,
            (v) => setState(() => _vsAllowAssignment = v),
          ),
          _vsPermTile(
            'Priority Listing',
            'Vendor appears higher in search results',
            _vsPriorityListing,
            (v) => setState(() => _vsPriorityListing = v),
          ),
          const SizedBox(height: 10),
          _label('Reduced Commission % (optional)'),
          const SizedBox(height: 4),
          TextField(
            controller: _vsCommissionPctCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDeco('Leave empty for default rate'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Switch(
                value: _vsIsActive,
                onChanged: (v) => setState(() => _vsIsActive = v),
                activeColor: AppColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                _vsIsActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: _vsIsActive
                      ? AppColors.success
                      : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _vsPermTile(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: value ? AppColors.primary.withValues(alpha: 0.04) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.border,
          width: 0.8,
        ),
      ),
      child: SwitchListTile(
        dense: true,
        title: Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
}
