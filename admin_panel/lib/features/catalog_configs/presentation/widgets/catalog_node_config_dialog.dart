import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/catalog_node_configs_repository.dart';
import '../../domain/models/catalog_node_config_model.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CatalogNodeConfigDialog
//
// Allows admin staff to set per-path or per-node module configuration
// (Tax, Loyalty, Scheduling, Commission) for a catalog node.
//
// Two scopes (admin must choose explicitly):
//   "This path only"        — relationship-scoped; affects this node ONLY when
//                             accessed via the specific parent shown in the title.
//                             Never leaks to the same node under another parent.
//   "All occurrences"       — node-scoped; affects this node regardless of the
//                             path the customer used to navigate to it.
//
// parentNodeId and parentNodeName are null when the tile has no parent context
// (root-level tiles), in which case only node-scoped config is available.
// ═══════════════════════════════════════════════════════════════════════════════

class CatalogNodeConfigDialog extends StatefulWidget {
  final String nodeId;
  final String nodeName;
  final String? parentNodeId;
  final String? parentNodeName;
  final bool hasChildren;

  const CatalogNodeConfigDialog({
    super.key,
    required this.nodeId,
    required this.nodeName,
    this.parentNodeId,
    this.parentNodeName,
    this.hasChildren = false,
  });

  @override
  State<CatalogNodeConfigDialog> createState() =>
      _CatalogNodeConfigDialogState();
}

class _CatalogNodeConfigDialogState extends State<CatalogNodeConfigDialog>
    with SingleTickerProviderStateMixin {
  final _repo = CatalogNodeConfigsRepository(Supabase.instance.client);

  late TabController _tabController;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Resolved relationship_id (null when no parent context or not found)
  String? _relationshipId;

  // Current configs keyed by module
  final Map<String, CatalogNodeConfigModel?> _relConfigs = {};
  final Map<String, CatalogNodeConfigModel?> _nodeConfigs = {};

  // Scope choice per module: true = relationship-scoped, false = node-scoped
  // Defaults to relationship-scoped when a parent context exists.
  final Map<String, bool> _useRelScope = {};

  // Scope as it was when _loadData() last ran — used to detect conversions in _save().
  final Map<String, bool> _savedScope = {};

  // Effective resolved config per module when no direct override exists.
  // Populated from resolve_catalog_module_config; null means no inherited config.
  final Map<String, Map<String, dynamic>?> _resolvedConfigs = {};

  // Whether the admin clicked "Create override" in a module tab.
  final Map<String, bool> _creatingOverride = {};

  // Whether "Apply to all child items" is checked per module.
  final Map<String, bool> _applyToChildren = {};

  // Form controllers per module
  // Tax
  final _taxValueCtrl = TextEditingController();
  String _taxType = 'percentage';
  final _taxNameCtrl = TextEditingController(text: 'GST');

  // Loyalty
  bool _loyaltyEarnEnabled = true;
  String _loyaltyRule = 'global';
  final _loyaltyFixedCtrl = TextEditingController();
  final _loyaltyPercentCtrl = TextEditingController();

  // Scheduling
  bool _schedEnabled = true;
  final List<bool> _schedDays = List.filled(7, true); // Sun–Sat
  final _schedMaxCtrl = TextEditingController(text: '5');
  final _schedSlotsCtrl = TextEditingController();

  // Commission
  final _commValueCtrl = TextEditingController();
  String _commType = 'percentage';

  static const _modules = ['tax', 'loyalty', 'scheduling', 'commission'];
  static const _tabLabels = ['Tax', 'Loyalty', 'Scheduling', 'Platform Commission'];
  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    for (final m in _modules) {
      _applyToChildren[m] = false;
    }
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
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Resolve relationship_id if parent context is available
      if (widget.parentNodeId != null) {
        _relationshipId = await _repo.fetchRelationshipId(
          widget.parentNodeId!,
          widget.nodeId,
        );
      }

      // Load existing configs
      List<CatalogNodeConfigModel> relCfgs = [];
      List<CatalogNodeConfigModel> nodeCfgs = [];

      if (_relationshipId != null) {
        relCfgs = await _repo.fetchForRelationship(_relationshipId!);
      }
      nodeCfgs = await _repo.fetchForNode(widget.nodeId);

      for (final m in _modules) {
        _relConfigs[m] =
            relCfgs.where((c) => c.module == m).firstOrNull;
        _nodeConfigs[m] =
            nodeCfgs.where((c) => c.module == m).firstOrNull;
        // A3: rel-scoped override exists → "This path only".
        // A4: node-scoped override exists (no rel) → "All occurrences".
        // A5: no override → default to path scope when parent context available.
        _useRelScope[m] = _relConfigs[m] != null
            ? true
            : (_nodeConfigs[m] != null ? false : _relationshipId != null);
        _savedScope[m] = _useRelScope[m]!;
      }

      // Resolve inherited config for modules that have no direct override at all.
      for (final m in _modules) {
        if (_relConfigs[m] == null && _nodeConfigs[m] == null) {
          try {
            _resolvedConfigs[m] = await _repo.resolveConfig(
                m, widget.nodeId, widget.parentNodeId);
          } catch (_) {
            _resolvedConfigs[m] = null;
          }
        } else {
          _resolvedConfigs[m] = null;
        }
      }

      // Populate form fields from existing configs (prefer active scope)
      _populateTax();
      _populateLoyalty();
      _populateScheduling();
      _populateCommission();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Reloads configs and repopulates form fields after save/delete.
  /// Does NOT touch [_useRelScope] — the admin's scope choice is preserved.
  Future<void> _refreshConfigs() async {
    List<CatalogNodeConfigModel> relCfgs = [];
    List<CatalogNodeConfigModel> nodeCfgs = [];
    if (_relationshipId != null) {
      relCfgs = await _repo.fetchForRelationship(_relationshipId!);
    }
    nodeCfgs = await _repo.fetchForNode(widget.nodeId);
    for (final m in _modules) {
      _relConfigs[m] = relCfgs.where((c) => c.module == m).firstOrNull;
      _nodeConfigs[m] = nodeCfgs.where((c) => c.module == m).firstOrNull;
    }
    for (final m in _modules) {
      if (_relConfigs[m] == null && _nodeConfigs[m] == null) {
        try {
          _resolvedConfigs[m] = await _repo.resolveConfig(
              m, widget.nodeId, widget.parentNodeId);
        } catch (_) {
          _resolvedConfigs[m] = null;
        }
      } else {
        _resolvedConfigs[m] = null;
      }
    }
    _populateTax();
    _populateLoyalty();
    _populateScheduling();
    _populateCommission();
  }

  CatalogNodeConfigModel? _activeConfig(String module) {
    final useRel = _useRelScope[module] ?? false;
    return useRel ? _relConfigs[module] : _nodeConfigs[module];
  }

  void _populateTax() {
    final cfg = _activeConfig('tax');
    if (cfg != null) {
      _taxNameCtrl.text = cfg.config['tax_name'] as String? ?? 'GST';
      _taxType = cfg.config['tax_type'] as String? ?? 'percentage';
      _taxValueCtrl.text =
          (cfg.config['tax_value'] as num?)?.toString() ?? '';
    }
  }

  void _populateLoyalty() {
    final cfg = _activeConfig('loyalty');
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
    final cfg = _activeConfig('scheduling');
    debugPrint('[DODO][SchedCfg] _populateScheduling: '
        'useRelScope=${_useRelScope['scheduling']}  cfg=${cfg != null ? 'found(id=${cfg.id})' : 'null'}');
    if (cfg != null) {
      _schedEnabled = cfg.config['is_enabled'] as bool? ?? true;
      final rawDays = cfg.config['working_days'];
      debugPrint('[DODO][SchedCfg] working_days raw=$rawDays  type=${rawDays?.runtimeType}');
      final days = (rawDays as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          {};
      debugPrint('[DODO][SchedCfg] days parsed=$days');
      // Always apply working_days from DB — removing the old `if (days.isNotEmpty)` guard
      // that caused the loop to be skipped when working_days is [] or null, leaving
      // _schedDays at its previous value instead of reflecting the saved state.
      for (int i = 0; i < 7; i++) {
        _schedDays[i] = days.contains(i);
      }
      debugPrint('[DODO][SchedCfg] _schedDays=${List.from(_schedDays)}');
      _schedMaxCtrl.text =
          (cfg.config['max_bookings_per_slot'] as num?)?.toString() ?? '5';
      final slots =
          (cfg.config['slots'] as List<dynamic>?)?.cast<String>() ?? [];
      _schedSlotsCtrl.text = slots.join(', ');
    }
  }

  void _populateCommission() {
    final cfg = _activeConfig('commission');
    if (cfg != null) {
      _commType = cfg.config['commission_type'] as String? ?? 'percentage';
      _commValueCtrl.text =
          (cfg.config['commission_value'] as num?)?.toString() ?? '';
    }
  }

  Future<void> _save(String module) async {
    final useRel = _useRelScope[module] ?? false;
    final applyToChildren = (_applyToChildren[module] ?? false) && widget.hasChildren;

    // Validate before anything else.
    if (useRel && _relationshipId == null) {
      setState(() {
        _error = 'Could not link this category to the item. Please refresh and try again.';
      });
      return;
    }

    // ── All confirmations happen HERE, before any database write ──────────────
    String? bulkMode; // null = normal save, otherwise 'subtree_only' | 'shared_everywhere'

    if (applyToChildren) {
      if (!mounted) return;
      final tabLabel = _tabLabels[_modules.indexOf(module)];

      // Step 1: first warning — confirm intent to override child items.
      final firstOk = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Override child settings?'),
          content: Text(
            'Saving will also clear existing $tabLabel overrides on all child items '
            'in this subtree so they inherit this setting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apply & Override'),
            ),
          ],
        ),
      );
      // Cancel at step 1: leave dialog open with all values intact, do nothing.
      if (firstOk != true || !mounted) return;

      // Step 2: scan for shared descendants (read-only, before any write).
      final sharedCount = await _repo.countSharedDescendants(widget.nodeId);
      if (!mounted) return;

      if (sharedCount > 0) {
        // Step 3: mode-choice dialog — only shown when shared descendants exist.
        final chosen = await _showSharedModeDialog(sharedCount, tabLabel);
        // Cancel at step 3: do nothing.
        if (chosen == null || !mounted) return;
        bulkMode = chosen;
      } else {
        bulkMode = 'subtree_only';
      }
    }
    // ── All confirmations complete. Now write. ────────────────────────────────

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = _buildConfig(module);
      final existing = _activeConfig(module);

      final model = CatalogNodeConfigModel(
        id: existing?.id ?? '',
        module: module,
        relationshipId: useRel ? _relationshipId : null,
        nodeId: useRel ? null : widget.nodeId,
        config: config,
        isEnabled: true,
      );

      await _repo.upsert(model);

      // Scope conversion: delete the old-scope config when the admin switched.
      // Only runs after a successful upsert — never deletes if the save failed.
      final wasUseRel = _savedScope[module] ?? useRel;
      if (useRel != wasUseRel) {
        final oldConfig = wasUseRel ? _relConfigs[module] : _nodeConfigs[module];
        if (oldConfig != null) {
          await _repo.deleteById(oldConfig.id);
        }
        _savedScope[module] = useRel;
      }

      await _refreshConfigs();
      _creatingOverride[module] = false;

      if (bulkMode != null && mounted) {
        final tabLabel = _tabLabels[_modules.indexOf(module)];
        final result = await _repo.bulkApplyConfigToSubtree(
          widget.nodeId, module, config, true,
          mode: bulkMode,
        );

        debugPrint(
          '[DODO][BulkConfig] node=${widget.nodeId} module=$module mode=$bulkMode '
          'deleted=${result.deleted} upserted=${result.upserted} '
          'skipped=${result.skipped}',
        );

        if (mounted) {
          setState(() => _applyToChildren[module] = false);
          final String note;
          if (bulkMode == 'shared_everywhere' && result.upserted > 0) {
            note = ' (${result.upserted} shared item${result.upserted == 1 ? '' : 's'} updated everywhere)';
          } else if (result.skipped > 0) {
            note = ' (${result.skipped} shared item${result.skipped == 1 ? '' : 's'} received path-specific override)';
          } else {
            note = '';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '$tabLabel settings saved and applied to child items$note.'),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${_tabLabels[_modules.indexOf(module)]} settings saved.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showSharedModeDialog(int sharedCount, String tabLabel) {
    String selected = 'subtree_only';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('Shared items found'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Some items under "${widget.nodeName}" also appear in other parts '
                  'of the catalog. Choose where you want to apply these settings.',
                ),
                const SizedBox(height: 6),
                Text(
                  '$sharedCount shared item${sharedCount == 1 ? '' : 's'} found.',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                _SharedModeOption(
                  title: 'Only this catalog section',
                  subtitle:
                      'Apply the $tabLabel setting only to items inside '
                      '"${widget.nodeName}". Other places where shared items '
                      'appear will remain unchanged.',
                  selected: selected == 'subtree_only',
                  onTap: () => setModal(() => selected = 'subtree_only'),
                ),
                const SizedBox(height: 8),
                _SharedModeOption(
                  title: 'Everywhere shared items appear',
                  subtitle:
                      'Also apply this $tabLabel setting to these shared items '
                      'everywhere they appear in the catalog.',
                  selected: selected == 'shared_everywhere',
                  onTap: () => setModal(() => selected = 'shared_everywhere'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(String module) async {
    final existing = _activeConfig(module);
    if (existing == null) return;
    setState(() => _saving = true);
    try {
      await _repo.deleteById(existing.id);
      await _refreshConfigs();
      _creatingOverride[module] = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_tabLabels[_modules.indexOf(module)]} settings removed — default settings will apply.')),
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
      default:
        return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasParent = widget.parentNodeId != null;
    final pathLabel = hasParent
        ? '${widget.parentNodeName ?? 'Parent'} → ${widget.nodeName}'
        : widget.nodeName;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────────
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
                          pathLabel,
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
              // ── Tabs ───────────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: _tabLabels
                    .map((l) => Tab(text: l))
                    .toList(),
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
                  children: _modules.map((m) => _buildModuleTab(m)).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModuleTab(String module) {
    final hasParent = widget.parentNodeId != null && _relationshipId != null;
    final useRel = _useRelScope[module] ?? false;
    final existing = _activeConfig(module);
    final inherited = _resolvedConfigs[module];
    final creating = _creatingOverride[module] ?? false;

    // Show edit form when a direct override exists, admin clicked "Create override",
    // or no inherited config is available to show in place of the form.
    final showForm = existing != null || creating || inherited == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Scope selector ────────────────────────────────────────────
          if (hasParent) ...[
            const Text(
              'Apply to',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    dense: true,
                    title: const Text(
                      'Only here',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      'Use this setting only for '
                      '${widget.parentNodeName ?? 'this category'} → ${widget.nodeName}.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: true,
                    groupValue: useRel,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() {
                        _useRelScope[module] = true;
                        _populateFromScope(module);
                      });
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<bool>(
                    dense: true,
                    title: const Text(
                      'Everywhere',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      'Use this setting for ${widget.nodeName} wherever it appears in the catalog.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: false,
                    groupValue: useRel,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() {
                        _useRelScope[module] = false;
                        _populateFromScope(module);
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No category selected — this setting applies to '
                      '${widget.nodeName} everywhere in the catalog.',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Inherited config card (read-only) ─────────────────────────
          // Only shown when no direct override exists AND an ancestor has a config.
          if (!showForm) ...[
            _buildInheritedCard(module, inherited),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _creatingOverride[module] = true;
                _populateFromInherited(module);
              }),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Set different settings here'),
            ),
          ],

          // ── Edit form (direct override or creating new) ────────────────
          if (showForm) ...[
            _buildModuleFields(module),

            if (widget.hasChildren) ...[
              const SizedBox(height: 16),
              _buildApplyToChildrenCheckbox(module),
            ],

            const SizedBox(height: 20),

            Row(
              children: [
                if (existing != null) ...[
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _delete(module),
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Use parent settings'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                  const Spacer(),
                ] else if (creating) ...[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _creatingOverride[module] = false;
                              _populateFromScope(module);
                            }),
                    child: const Text('Cancel'),
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

            if (existing == null && !creating)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No custom settings — default ${_tabLabels[_modules.indexOf(module)]} settings will apply.',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _populateFromScope(String module) {
    switch (module) {
      case 'tax':
        _populateTax();
      case 'loyalty':
        _populateLoyalty();
      case 'scheduling':
        _populateScheduling();
      case 'commission':
        _populateCommission();
    }
  }

  // ── Inherited config helpers ────────────────────────────────────────────────

  Widget _buildInheritedCard(String module, Map<String, dynamic>? cfg) {
    if (cfg == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 14, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Using parent settings',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in _inheritedConfigLines(module, cfg))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
          const SizedBox(height: 8),
          Text(
            'This setting comes from ${widget.parentNodeName ?? 'a parent category'}.',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  List<String> _inheritedConfigLines(
      String module, Map<String, dynamic> cfg) {
    switch (module) {
      case 'tax':
        final name = cfg['tax_name'] as String? ?? 'GST';
        final type = cfg['tax_type'] as String? ?? 'percentage';
        final value = cfg['tax_value'] as num? ?? 0;
        return [
          'Tax name: $name',
          'Type: ${type == 'percentage' ? 'Percentage (%)' : 'Fixed (₹)'}',
          '${type == 'percentage' ? 'Rate' : 'Amount'}: $value'
              '${type == 'percentage' ? '%' : ' ₹'}',
        ];
      case 'loyalty':
        final enabled = cfg['earn_enabled'] as bool? ?? true;
        if (!enabled) return ['Loyalty earn: Disabled'];
        final rule = cfg['earn_rule'] as String? ?? 'global';
        if (rule == 'fixed') {
          final pts = cfg['fixed_points'];
          return [
            'Earn rule: Fixed points',
            'Points per booking: ${pts ?? '—'}',
          ];
        } else if (rule == 'percentage') {
          final per = cfg['earn_per_100'];
          return [
            'Earn rule: Points per ₹100 spent',
            'Points per ₹100: ${per ?? '—'}',
          ];
        }
        return ['Earn rule: Global rate'];
      case 'scheduling':
        final enabled = cfg['is_enabled'] as bool? ?? true;
        if (!enabled) return ['Scheduling: Disabled'];
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final days = (cfg['working_days'] as List<dynamic>?)
                ?.map((e) => dayNames[(e as num).toInt()])
                .join(', ') ??
            '';
        final max = cfg['max_bookings_per_slot'] as num? ?? 5;
        final slots =
            (cfg['slots'] as List<dynamic>?)?.cast<String>().join(', ') ??
                '—';
        return [
          if (days.isNotEmpty) 'Working days: $days',
          'Max bookings per slot: $max',
          'Slots: $slots',
        ];
      case 'commission':
        final type = cfg['commission_type'] as String? ?? 'percentage';
        final value = cfg['commission_value'] as num? ?? 0;
        return [
          'Type: ${type == 'percentage' ? 'Percentage (%)' : 'Fixed (₹)'}',
          '${type == 'percentage' ? 'Rate' : 'Amount'}: $value'
              '${type == 'percentage' ? '%' : ' ₹'}',
        ];
      default:
        return [];
    }
  }

  void _populateFromInherited(String module) {
    final cfg = _resolvedConfigs[module];
    if (cfg == null) return;
    switch (module) {
      case 'tax':
        _taxNameCtrl.text = cfg['tax_name'] as String? ?? 'GST';
        _taxType = cfg['tax_type'] as String? ?? 'percentage';
        _taxValueCtrl.text = (cfg['tax_value'] as num?)?.toString() ?? '';
      case 'loyalty':
        _loyaltyEarnEnabled = cfg['earn_enabled'] as bool? ?? true;
        _loyaltyRule = cfg['earn_rule'] as String? ?? 'global';
        _loyaltyFixedCtrl.text =
            (cfg['fixed_points'] as num?)?.toString() ?? '';
        _loyaltyPercentCtrl.text =
            (cfg['earn_per_100'] as num?)?.toString() ?? '';
      case 'scheduling':
        _schedEnabled = cfg['is_enabled'] as bool? ?? true;
        final days = (cfg['working_days'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toSet() ??
            {};
        for (int i = 0; i < 7; i++) {
          _schedDays[i] = days.contains(i);
        }
        _schedMaxCtrl.text =
            (cfg['max_bookings_per_slot'] as num?)?.toString() ?? '5';
        final slots =
            (cfg['slots'] as List<dynamic>?)?.cast<String>() ?? [];
        _schedSlotsCtrl.text = slots.join(', ');
      case 'commission':
        _commType = cfg['commission_type'] as String? ?? 'percentage';
        _commValueCtrl.text =
            (cfg['commission_value'] as num?)?.toString() ?? '';
    }
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
        TextField(
          controller: _taxNameCtrl,
          decoration: _inputDeco('e.g. GST'),
        ),
        const SizedBox(height: 12),
        _label('Tax Type'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'percentage', label: Text('Percentage (%)')),
            ButtonSegment(value: 'fixed', label: Text('Fixed (₹)')),
          ],
          selected: {_taxType},
          onSelectionChanged: (s) =>
              setState(() => _taxType = s.first),
        ),
        const SizedBox(height: 12),
        _label(_taxType == 'percentage' ? 'Tax Rate (%)' : 'Fixed Amount (₹)'),
        const SizedBox(height: 4),
        TextField(
          controller: _taxValueCtrl,
          decoration: _inputDeco(
              _taxType == 'percentage' ? 'e.g. 12' : 'e.g. 50'),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
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
          title: const Text('Loyalty Earn Enabled',
              style: TextStyle(fontSize: 13)),
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
                value: 'percentage', child: Text('Points per ₹100')),
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
          _label('Points per ₹100 spent'),
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
          title: const Text('Scheduling Enabled',
              style: TextStyle(fontSize: 13)),
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
              label: Text(_dayLabels[i],
                  style: const TextStyle(fontSize: 12)),
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
            ButtonSegment(value: 'fixed', label: Text('Fixed (₹)')),
          ],
          selected: {_commType},
          onSelectionChanged: (s) =>
              setState(() => _commType = s.first),
        ),
        const SizedBox(height: 12),
        _label(
            _commType == 'percentage' ? 'Platform Commission Rate (%)' : 'Fixed Amount (₹)'),
        const SizedBox(height: 4),
        TextField(
          controller: _commValueCtrl,
          decoration: _inputDeco(
              _commType == 'percentage' ? 'e.g. 15' : 'e.g. 100'),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      ],
    );
  }

  Widget _buildApplyToChildrenCheckbox(String module) {
    final checked = _applyToChildren[module] ?? false;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: checked ? AppColors.primary : AppColors.border,
          width: checked ? 1.2 : 0.8,
        ),
        borderRadius: BorderRadius.circular(8),
        color: checked ? AppColors.primary.withValues(alpha: 0.05) : null,
      ),
      child: CheckboxListTile(
        dense: true,
        value: checked,
        onChanged: (v) => setState(() => _applyToChildren[module] = v ?? false),
        title: const Text(
          'Apply to all child items',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: const Text(
          'Removes existing overrides on child items so they inherit this setting. '
          'Items shared across other catalog paths receive a path-specific override '
          'that does not affect their other occurrences.',
          style: TextStyle(fontSize: 11),
        ),
        activeColor: AppColors.primary,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

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
}

// ── Shared-mode option card used inside the mode-choice dialog ─────────────────

class _SharedModeOption extends StatelessWidget {
  const _SharedModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 0.8,
          ),
          borderRadius: BorderRadius.circular(8),
          color: selected ? AppColors.primary.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
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
