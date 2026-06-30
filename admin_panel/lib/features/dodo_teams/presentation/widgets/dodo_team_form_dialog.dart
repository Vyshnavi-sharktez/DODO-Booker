import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/dodo_team.dart';

const _statusOptions = [
  ('Available', 'Available'),
  ('Busy', 'Busy'),
  ('Inactive', 'Inactive'),
];

class DodoTeamFormDialog extends StatefulWidget {
  final DodoTeam? existing;
  final Future<void> Function({
    required String teamName,
    String? supervisorName,
    String? phone,
    String? email,
    String? locality,
    required int membersCount,
    required String status,
  }) onSave;

  const DodoTeamFormDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<DodoTeamFormDialog> createState() => _DodoTeamFormDialogState();
}

class _DodoTeamFormDialogState extends State<DodoTeamFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _teamNameCtrl;
  late final TextEditingController _supervisorCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _localityCtrl;
  late final TextEditingController _membersCtrl;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _teamNameCtrl = TextEditingController(text: e?.teamName ?? '');
    _supervisorCtrl = TextEditingController(text: e?.supervisorName ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _localityCtrl = TextEditingController(text: e?.locality ?? '');
    _membersCtrl = TextEditingController(
      text: e != null ? e.membersCount.toString() : '0',
    );
    // Use the DB value directly; fall back to 'Available' if unrecognized.
    final existingStatus = e?.status ?? 'Available';
    _status = _statusOptions.any((o) => o.$1 == existingStatus)
        ? existingStatus
        : 'Available';
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _supervisorCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _localityCtrl.dispose();
    _membersCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final membersCount = int.tryParse(_membersCtrl.text.trim()) ?? 0;
      await widget.onSave(
        teamName: _teamNameCtrl.text.trim(),
        supervisorName: _supervisorCtrl.text.trim().isEmpty
            ? null
            : _supervisorCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email:
            _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        locality: _localityCtrl.text.trim().isEmpty
            ? null
            : _localityCtrl.text.trim(),
        membersCount: membersCount,
        status: _status,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
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
                    isEdit ? Icons.edit_rounded : Icons.groups_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Team' : 'New Team',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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

            // ── Form ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Team Name
                      TextFormField(
                        controller: _teamNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Team Name *',
                          hintText: 'e.g. Alpha Team',
                          prefixIcon: Icon(Icons.groups_rounded),
                        ),
                        textCapitalization: TextCapitalization.words,
                        enabled: !_saving,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Supervisor Name | Phone
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _supervisorCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Supervisor Name',
                                hintText: 'Full name',
                                prefixIcon: Icon(Icons.person_rounded),
                                helperText: 'Optional',
                              ),
                              textCapitalization: TextCapitalization.words,
                              enabled: !_saving,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                                hintText: '+91 …',
                                prefixIcon: Icon(Icons.phone_rounded),
                                helperText: 'Optional',
                              ),
                              keyboardType: TextInputType.phone,
                              enabled: !_saving,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d\+\-\s\(\)]')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Email | Locality
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'team@example.com',
                                prefixIcon: Icon(Icons.email_rounded),
                                helperText: 'Optional',
                              ),
                              keyboardType: TextInputType.emailAddress,
                              enabled: !_saving,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                    .hasMatch(v.trim())) {
                                  return 'Invalid email';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _localityCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Locality',
                                hintText: 'Area / Locality',
                                prefixIcon: Icon(Icons.location_on_rounded),
                                helperText: 'Optional',
                              ),
                              textCapitalization: TextCapitalization.words,
                              enabled: !_saving,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Members Count | Status
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _membersCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Members *',
                                hintText: '0',
                                prefixIcon: Icon(Icons.people_rounded),
                              ),
                              keyboardType: TextInputType.number,
                              enabled: !_saving,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final n = int.tryParse(v.trim());
                                if (n == null || n < 0) return 'Must be ≥ 0';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _status,
                              decoration: const InputDecoration(
                                labelText: 'Status *',
                                prefixIcon: Icon(Icons.flag_rounded),
                              ),
                              items: _statusOptions
                                  .map((s) => DropdownMenuItem(
                                        value: s.$1,
                                        child: Text(s.$2),
                                      ))
                                  .toList(),
                              onChanged: _saving
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        setState(() => _status = v);
                                      }
                                    },
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Add Team'),
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
