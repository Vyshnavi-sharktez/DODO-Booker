import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/availability_block.dart';

class AvailabilityBlockDialog extends StatefulWidget {
  const AvailabilityBlockDialog({super.key, this.existing});
  final AvailabilityBlock? existing;

  @override
  State<AvailabilityBlockDialog> createState() =>
      _AvailabilityBlockDialogState();
}

class _AvailabilityBlockDialogState extends State<AvailabilityBlockDialog> {
  final _client = Supabase.instance.client;

  String _scope = 'global';
  String? _nodeId;
  String? _vendorId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isFullDay = true;
  final _slotsController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isEnabled = true;

  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _vendors = [];
  bool _loadingNodes = false;
  bool _loadingVendors = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _scope = b.scope;
      _nodeId = b.nodeId;
      _vendorId = b.vendorId;
      _startDate = b.startDate;
      _endDate = b.endDate;
      _isFullDay = b.isFullDay;
      _slotsController.text = b.blockedSlots?.join(', ') ?? '';
      _reasonController.text = b.reason ?? '';
      _isEnabled = b.isEnabled;
    }
    _loadNodes();
    _loadVendors();
  }

  @override
  void dispose() {
    _slotsController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadNodes() async {
    setState(() => _loadingNodes = true);
    try {
      final rows = await _client
          .from('catalog_nodes')
          .select('id, name, is_bookable')
          .order('name');
      setState(() => _nodes = (rows as List).cast<Map<String, dynamic>>());
      if (_nodeId != null) {
        // ensure _nodeId still refers to a valid entry after reload
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingNodes = false);
    }
  }

  Future<void> _loadVendors() async {
    setState(() => _loadingVendors = true);
    try {
      final rows = await _client
          .from('vendors')
          .select('id, business_name')
          .order('business_name');
      setState(() => _vendors = (rows as List).cast<Map<String, dynamic>>());
      if (_vendorId != null) {
        // ensure _vendorId still refers to a valid entry after reload
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingVendors = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final first = isStart ? DateTime(2020) : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(2099),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  List<String>? _parseSlots() {
    final raw = _slotsController.text.trim();
    if (raw.isEmpty) return null;
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _submit() {
    setState(() => _error = null);
    if (_scope == 'category' || _scope == 'service') {
      if (_nodeId == null) {
        setState(() => _error = 'Select a ${_scope == 'category' ? 'category' : 'service'} node.');
        return;
      }
    }
    if (_scope == 'vendor' && _vendorId == null) {
      setState(() => _error = 'Select a vendor.');
      return;
    }

    final slots = _isFullDay ? null : _parseSlots();
    if (!_isFullDay && (slots == null || slots.isEmpty)) {
      setState(() => _error = 'Enter at least one slot label for a partial-day block.');
      return;
    }

    final now = DateTime.now().toUtc();
    final existing = widget.existing;
    final block = AvailabilityBlock(
      id: existing?.id ?? '',
      scope: _scope,
      nodeId: (_scope == 'category' || _scope == 'service') ? _nodeId : null,
      vendorId: _scope == 'vendor' ? _vendorId : null,
      startDate: _startDate,
      endDate: _endDate,
      blockedSlots: slots,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
      isEnabled: _isEnabled,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.of(context).pop(block);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final nodeLabel = _scope == 'category' ? 'Category Node' : 'Service Node';
    final scopeNodes = _scope == 'category'
        ? _nodes.where((n) => n['is_bookable'] == false).toList()
        : _nodes.where((n) => n['is_bookable'] == true).toList();

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        isEdit ? 'Edit Availability Block' : 'New Availability Block',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Scope ──────────────────────────────────────────────────────
              _Label('Scope'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _scope,
                decoration: _inputDecor(),
                items: const [
                  DropdownMenuItem(value: 'global', child: Text('Global — all services')),
                  DropdownMenuItem(value: 'category', child: Text('Category — all services under category')),
                  DropdownMenuItem(value: 'service', child: Text('Service — single service')),
                  DropdownMenuItem(value: 'vendor', child: Text('Vendor — all bookings by vendor')),
                ],
                onChanged: (v) => setState(() {
                  _scope = v!;
                  _nodeId = null;
                  _vendorId = null;
                }),
              ),
              const SizedBox(height: 14),

              // ── Node picker (category / service scope) ─────────────────────
              if (_scope == 'category' || _scope == 'service') ...[
                _Label(nodeLabel),
                const SizedBox(height: 6),
                _loadingNodes
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        value: _nodeId,
                        isExpanded: true,
                        decoration: _inputDecor(hint: 'Select node…'),
                        items: scopeNodes
                            .map((n) => DropdownMenuItem<String>(
                                  value: n['id'] as String,
                                  child: Text(n['name'] as String,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _nodeId = v),
                      ),
                const SizedBox(height: 14),
              ],

              // ── Vendor picker ──────────────────────────────────────────────
              if (_scope == 'vendor') ...[
                _Label('Vendor'),
                const SizedBox(height: 6),
                _loadingVendors
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        value: _vendorId,
                        isExpanded: true,
                        decoration: _inputDecor(hint: 'Select vendor…'),
                        items: _vendors
                            .map((v) => DropdownMenuItem<String>(
                                  value: v['id'] as String,
                                  child: Text(v['business_name'] as String,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _vendorId = v),
                      ),
                const SizedBox(height: 14),
              ],

              // ── Date range ─────────────────────────────────────────────────
              _Label('Date Range'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'Start',
                      date: _startDate,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      label: 'End',
                      date: _endDate,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Full-day vs partial-day ────────────────────────────────────
              _Label('Block Type'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _TypeChip(
                      label: 'Full Day',
                      selected: _isFullDay,
                      onTap: () => setState(() => _isFullDay = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeChip(
                      label: 'Specific Slots',
                      selected: !_isFullDay,
                      onTap: () => setState(() => _isFullDay = false),
                    ),
                  ),
                ],
              ),
              if (!_isFullDay) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _slotsController,
                  decoration: _inputDecor(
                    hint: '09:00 AM, 10:00 AM, 11:00 AM',
                    label: 'Slot Labels (comma-separated)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter slot labels exactly as shown in the schedule (e.g. "09:00 AM").',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 14),

              // ── Reason ─────────────────────────────────────────────────────
              _Label('Reason (optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _reasonController,
                decoration: _inputDecor(hint: 'e.g. Public holiday, maintenance…'),
                maxLines: 2,
              ),
              const SizedBox(height: 14),

              // ── Enable toggle ──────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Enable this block immediately',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isEnabled,
                    onChanged: (v) => setState(() => _isEnabled = v),
                    activeThumbColor: AppColors.success,
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                _ErrorRow(message: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(isEdit ? 'Save Changes' : 'Create Block'),
        ),
      ],
    );
  }

  InputDecoration _inputDecor({String? hint, String? label}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      );
}

class _DateButton extends StatelessWidget {
  const _DateButton(
      {required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(s,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.calendar_today_rounded,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ],
        ),
      );
}
