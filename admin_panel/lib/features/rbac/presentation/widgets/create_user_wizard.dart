import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/presentation/widgets/vendor_location_picker_dialog.dart';
import '../../application/providers/rbac_providers.dart';

// ── Staged document helper ────────────────────────────────────────────────────

class _StagedDoc {
  final String docType;
  final String displayType;
  final String fileName;
  final Uint8List bytes;
  final String mimeType;

  const _StagedDoc({
    required this.docType,
    required this.displayType,
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });
}

const _docTypes = [
  ('aadhaar_card', 'Aadhaar Card'),
  ('pan_card', 'PAN Card'),
  ('gst_certificate', 'GST Certificate'),
  ('business_license', 'Business License'),
  ('other', 'Other'),
];

// ── Wizard entry point ────────────────────────────────────────────────────────

class CreateUserWizard extends ConsumerStatefulWidget {
  const CreateUserWizard({super.key});

  @override
  ConsumerState<CreateUserWizard> createState() => _CreateUserWizardState();
}

class _CreateUserWizardState extends ConsumerState<CreateUserWizard> {
  int _step = 0;
  String? _userType; // 'admin' | 'vendor'

  // Common fields
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  double? _latitude;
  double? _longitude;

  // Admin-specific
  String? _selectedRoleId;

  // Vendor-specific
  final _businessName = TextEditingController();
  final _city = TextEditingController();

  // Documents (vendor only)
  final _docs = <_StagedDoc>[];
  String _stagingDocType = 'aadhaar_card';

  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _businessName.dispose();
    _city.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _next() {
    if (_step == 0) {
      if (_userType == null) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      if (!_formKey.currentState!.validate()) return;
      setState(() => _step = 2);
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Map picker ──────────────────────────────────────────────────────────────

  Future<void> _pickOnMap() async {
    final result = await showDialog<VendorLocationPickerResult>(
      context: context,
      builder: (_) => VendorLocationPickerDialog(
        initialLatitude: _latitude,
        initialLongitude: _longitude,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      if (result.address?.isNotEmpty == true) _address.text = result.address!;
      if (result.city?.isNotEmpty == true) _city.text = result.city!;
    });
  }

  // ── Document staging ────────────────────────────────────────────────────────

  Future<void> _addDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final existing = _docs.indexWhere((d) => d.docType == _stagingDocType);
    final staged = _StagedDoc(
      docType: _stagingDocType,
      displayType: _docTypes.firstWhere((t) => t.$1 == _stagingDocType).$2,
      fileName: file.name,
      bytes: file.bytes!,
      mimeType: file.extension == 'pdf' ? 'application/pdf' : 'image/${file.extension}',
    );

    setState(() {
      if (existing >= 0) {
        _docs[existing] = staged;
      } else {
        _docs.add(staged);
      }
    });
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final s = e.toString();
    const prefix = 'Exception: ';
    return s.startsWith(prefix) ? s.substring(prefix.length) : s;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      if (_userType == 'admin') {
        final tempPassword = await _saveAdmin();
        if (mounted) {
          await _showTempPasswordDialog(
            email: _email.text.trim(),
            tempPassword: tempPassword,
          );
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        await _saveVendor();
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _saveError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _saveAdmin() async {
    return ref.read(rbacAdminUsersNotifierProvider.notifier).createAdminUser(
          fullName: _fullName.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : '+91${_phone.text.trim()}',
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          latitude: _latitude,
          longitude: _longitude,
          roleId: _selectedRoleId,
        );
  }

  Future<void> _showTempPasswordDialog({
    required String email,
    required String tempPassword,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TempPasswordDialog(
        email: email,
        tempPassword: tempPassword,
      ),
    );
  }

  Future<void> _saveVendor() async {
    final phone = '+91${_phone.text.trim()}';
    final businessName = _businessName.text.trim().isNotEmpty
        ? _businessName.text.trim()
        : _fullName.text.trim();

    await ref.read(vendorsNotifierProvider.notifier).createVendor(
          businessName: businessName,
          ownerName: _fullName.text.trim(),
          phone: phone,
          email: _email.text.trim(),
          city: _city.text.trim().isNotEmpty ? _city.text.trim() : 'Unknown',
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          status: 'active',
          isActive: true,
          latitude: _latitude,
          longitude: _longitude,
        );

    final supabase = Supabase.instance.client;

    // Upload staged documents (non-fatal)
    if (_docs.isNotEmpty) {
      final vendorRows = await supabase
          .from('vendors')
          .select('id')
          .eq('phone', phone)
          .limit(1);
      if (vendorRows.isNotEmpty) {
        final vendorId = vendorRows.first['id'] as String;
        await _uploadDocuments(vendorId);
      }
    }
  }

  Future<void> _uploadDocuments(String vendorId) async {
    final supabase = Supabase.instance.client;
    for (final doc in _docs) {
      try {
        final path = '$vendorId/${doc.docType}';
        await supabase.storage.from('vendor-documents').uploadBinary(
              path,
              doc.bytes,
              fileOptions: FileOptions(contentType: doc.mimeType, upsert: true),
            );
        final rawUrl = supabase.storage
            .from('vendor-documents')
            .getPublicUrl(path);
        final url = '$rawUrl?v=${DateTime.now().millisecondsSinceEpoch}';
        await supabase.from('vendor_documents').upsert(
          {
            'vendor_id': vendorId,
            'document_type': doc.docType,
            'document_url': url,
            'verification_status': 'pending',
          },
          onConflict: 'vendor_id,document_type',
        );
      } catch (_) {}
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, minWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(step: _step, userType: _userType),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _step == 0
                    ? _TypeStep(
                        selected: _userType,
                        onSelect: (t) => setState(() => _userType = t),
                      )
                    : _step == 1
                        ? Form(
                            key: _formKey,
                            child: _userType == 'admin'
                                ? _AdminDetailsStep(
                                    fullName: _fullName,
                                    email: _email,
                                    phone: _phone,
                                    address: _address,
                                    latitude: _latitude,
                                    longitude: _longitude,
                                    selectedRoleId: _selectedRoleId,
                                    onRoleChanged: (r) =>
                                        setState(() => _selectedRoleId = r),
                                    onPickMap: _pickOnMap,
                                  )
                                : _VendorDetailsStep(
                                    fullName: _fullName,
                                    businessName: _businessName,
                                    email: _email,
                                    phone: _phone,
                                    address: _address,
                                    city: _city,
                                    latitude: _latitude,
                                    longitude: _longitude,
                                    onPickMap: _pickOnMap,
                                  ),
                          )
                        : _DocumentsStep(
                            userType: _userType!,
                            docs: _docs,
                            stagingDocType: _stagingDocType,
                            onDocTypeChanged: (t) =>
                                setState(() => _stagingDocType = t),
                            onAddDocument: _addDocument,
                            onRemoveDoc: (i) =>
                                setState(() => _docs.removeAt(i)),
                          ),
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Text(
                  _saveError!,
                  style:
                      TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            _Footer(
              step: _step,
              saving: _saving,
              canNext: _step == 0 ? _userType != null : true,
              onBack: _step > 0 ? _back : null,
              onNext: _step < 2 ? _next : null,
              onSave: _step == 2 ? _save : null,
              onCancel: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step indicator header ─────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.step, required this.userType});
  final int step;
  final String? userType;

  @override
  Widget build(BuildContext context) {
    final steps = ['Type', 'Details', 'Documents'];
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Create User',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(steps.length, (i) {
              final active = i == step;
              final done = i < step;
              return Expanded(
                child: Row(
                  children: [
                    if (i > 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: done
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active || done
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                          ),
                          child: Center(
                            child: done
                                ? Icon(Icons.check_rounded,
                                    size: 16, color: AppColors.primary)
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? AppColors.primary
                                          : Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          steps[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: active || done
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: done
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.saving,
    required this.canNext,
    required this.onCancel,
    this.onBack,
    this.onNext,
    this.onSave,
  });

  final int step;
  final bool saving;
  final bool canNext;
  final VoidCallback onCancel;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text('Cancel'),
          ),
          const Spacer(),
          if (onBack != null)
            OutlinedButton(
              onPressed: saving ? null : onBack,
              child: const Text('Back'),
            ),
          if (onBack != null) const SizedBox(width: 8),
          if (onNext != null)
            FilledButton(
              onPressed: (saving || !canNext) ? null : onNext,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('Next'),
            ),
          if (onSave != null)
            FilledButton(
              onPressed: saving ? null : onSave,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
    );
  }
}

// ── Step 1: Type ──────────────────────────────────────────────────────────────

class _TypeStep extends StatelessWidget {
  const _TypeStep({required this.selected, required this.onSelect});
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select account type',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose whether to create an admin or vendor account.',
          style:
              TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _TypeCard(
                icon: Icons.admin_panel_settings_rounded,
                label: 'Admin',
                description: 'Creates an administrative account with RBAC permissions.',
                selected: selected == 'admin',
                onTap: () => onSelect('admin'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _TypeCard(
                icon: Icons.store_rounded,
                label: 'Vendor',
                description: 'Creates a service provider account with OTP login.',
                selected: selected == 'vendor',
                onTap: () => onSelect('vendor'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? AppColors.primary.withValues(alpha: 0.05)
              : AppColors.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color:
                    selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if (selected) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Selected',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Step 2 – Admin Details ────────────────────────────────────────────────────

class _AdminDetailsStep extends ConsumerWidget {
  const _AdminDetailsStep({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.selectedRoleId,
    required this.onRoleChanged,
    required this.onPickMap,
  });

  final TextEditingController fullName;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController address;
  final double? latitude;
  final double? longitude;
  final String? selectedRoleId;
  final ValueChanged<String?> onRoleChanged;
  final VoidCallback onPickMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(rolesProvider);
    final roles = rolesAsync.valueOrNull?.where((r) => r.isActive).toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Admin Details'),
        const SizedBox(height: 20),
        _nameEmailRow(fullName, email),
        const SizedBox(height: 16),
        _phoneField(phone),
        const SizedBox(height: 16),
        _addressWithMap(address, latitude, longitude, onPickMap),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: selectedRoleId,
          decoration: const InputDecoration(
            labelText: 'Role *',
            prefixIcon: Icon(Icons.shield_rounded),
          ),
          items: roles.isEmpty
              ? [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No roles available'),
                  )
                ]
              : roles
                  .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name),
                      ))
                  .toList(),
          onChanged: onRoleChanged,
          validator: (v) => v == null ? 'Select a role' : null,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A temporary password will be generated. Share it securely with the new admin — they can change it after their first login.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 2 – Vendor Details ───────────────────────────────────────────────────

class _VendorDetailsStep extends StatelessWidget {
  const _VendorDetailsStep({
    required this.fullName,
    required this.businessName,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.onPickMap,
  });

  final TextEditingController fullName;
  final TextEditingController businessName;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController city;
  final double? latitude;
  final double? longitude;
  final VoidCallback onPickMap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Vendor Details'),
        const SizedBox(height: 20),
        _nameEmailRow(fullName, email),
        const SizedBox(height: 16),
        TextFormField(
          controller: businessName,
          decoration: const InputDecoration(
            labelText: 'Business Name *',
            prefixIcon: Icon(Icons.store_rounded),
          ),
          textCapitalization: TextCapitalization.words,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        _phoneField(phone),
        const SizedBox(height: 16),
        _addressWithMap(address, latitude, longitude, onPickMap),
        const SizedBox(height: 16),
        TextFormField(
          controller: city,
          decoration: const InputDecoration(
            labelText: 'City',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_android_rounded,
                  size: 16, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vendor logs in via phone OTP in the Vendor App. Default OTP "000000" is set; communicate it to the vendor.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 3: Documents ─────────────────────────────────────────────────────────

class _DocumentsStep extends StatelessWidget {
  const _DocumentsStep({
    required this.userType,
    required this.docs,
    required this.stagingDocType,
    required this.onDocTypeChanged,
    required this.onAddDocument,
    required this.onRemoveDoc,
  });

  final String userType;
  final List<_StagedDoc> docs;
  final String stagingDocType;
  final ValueChanged<String> onDocTypeChanged;
  final VoidCallback onAddDocument;
  final ValueChanged<int> onRemoveDoc;

  @override
  Widget build(BuildContext context) {
    if (userType == 'admin') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Documents'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No documents are required for admin accounts. Click Save to create the account.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Documents'),
        const SizedBox(height: 6),
        Text(
          'Optional. Documents can also be uploaded from the Vendor App.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Add document row
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: stagingDocType,
                decoration: const InputDecoration(
                  labelText: 'Document Type',
                  prefixIcon: Icon(Icons.description_outlined),
                  isDense: true,
                ),
                items: _docTypes
                    .map((t) => DropdownMenuItem(
                          value: t.$1,
                          child: Text(t.$2),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onDocTypeChanged(v);
                },
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onAddDocument,
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: const Text('Select File'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Staged docs list
        if (docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: Text(
                'No documents added yet.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          )
        else
          ...docs.asMap().entries.map(
                (e) => _DocTile(
                  doc: e.value,
                  onRemove: () => onRemoveDoc(e.key),
                ),
              ),
      ],
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc, required this.onRemove});
  final _StagedDoc doc;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.displayType,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  doc.fileName,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ── Temp-password dialog ──────────────────────────────────────────────────────

class _TempPasswordDialog extends StatelessWidget {
  const _TempPasswordDialog({
    required this.email,
    required this.tempPassword,
  });

  final String email;
  final String tempPassword;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 22),
          const SizedBox(width: 8),
          const Text('Admin Account Created'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this temporary password securely with the new admin. '
            'They will be prompted to change it after their first login.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _LabeledValue(label: 'Email', value: email),
          const SizedBox(height: 10),
          _LabeledValue(
            label: 'Temporary Password',
            value: tempPassword,
            monospace: true,
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Password & Close'),
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: tempPassword));
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: monospace ? 'monospace' : null,
              letterSpacing: monospace ? 1.2 : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared field helpers ──────────────────────────────────────────────────────

Widget _sectionTitle(BuildContext context, String title) {
  return Text(
    title,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600),
  );
}

Widget _nameEmailRow(
    TextEditingController fullName, TextEditingController email) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextFormField(
          controller: fullName,
          decoration: const InputDecoration(
            labelText: 'Full Name *',
            prefixIcon: Icon(Icons.person_rounded),
          ),
          textCapitalization: TextCapitalization.words,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: TextFormField(
          controller: email,
          decoration: const InputDecoration(
            labelText: 'Email *',
            prefixIcon: Icon(Icons.email_rounded),
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
              return 'Invalid email';
            }
            return null;
          },
        ),
      ),
    ],
  );
}

Widget _phoneField(TextEditingController controller) {
  return PhoneInputField(
    controller: controller,
    labelText: 'Phone *',
    hintText: 'Phone Number',
    validator: (v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      if (v.trim().length < 10) return 'Enter a valid 10-digit number';
      return null;
    },
  );
}

Widget _addressWithMap(
  TextEditingController address,
  double? latitude,
  double? longitude,
  VoidCallback onPickMap,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: address,
              decoration: InputDecoration(
                labelText: 'Address *',
                prefixIcon: const Icon(Icons.location_pin),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  borderSide:
                      BorderSide(color: AppColors.accent, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  borderSide: BorderSide(color: AppColors.error),
                ),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
          ),
          InkWell(
            onTap: onPickMap,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: AppColors.primary),
              ),
              child: const Icon(Icons.map_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
      if (latitude != null && longitude != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 13, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                style: TextStyle(
                    fontSize: 11, color: AppColors.success),
              ),
            ],
          ),
        ),
    ],
  );
}
