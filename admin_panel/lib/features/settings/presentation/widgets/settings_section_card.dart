import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/settings_providers.dart';
import '../../domain/models/settings_defaults.dart';

// ── Field / Section definition types ─────────────────────────────────────────

enum SettingFieldType { text, email, phone, integer, decimal, percent, toggle, dropdown }

class SettingFieldDef {
  final String key;
  final String label;
  final String? hint;
  final SettingFieldType type;
  final String? unit;
  final List<String>? options;
  final double? min;
  final double? max;

  const SettingFieldDef({
    required this.key,
    required this.label,
    this.hint,
    required this.type,
    this.unit,
    this.options,
    this.min,
    this.max,
  });
}

class SettingSectionDef {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<SettingFieldDef> fields;

  const SettingSectionDef({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.fields,
  });
}

bool _isTextField(SettingFieldType t) =>
    t != SettingFieldType.toggle && t != SettingFieldType.dropdown;

// ── Section card ──────────────────────────────────────────────────────────────

class SettingsSectionCard extends ConsumerStatefulWidget {
  const SettingsSectionCard({required super.key, required this.section});
  final SettingSectionDef section;

  @override
  ConsumerState<SettingsSectionCard> createState() =>
      _SettingsSectionCardState();
}

class _SettingsSectionCardState extends ConsumerState<SettingsSectionCard> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  final Map<String, String> _dropdownValues = {};

  bool _dirty = false;
  bool _saving = false;
  Map<String, String>? _lastApplied;

  @override
  void initState() {
    super.initState();
    // Pre-fill with defaults; updated when settings load.
    for (final field in widget.section.fields) {
      final def = kSettingDefaults[field.key] ?? '';
      if (_isTextField(field.type)) {
        _controllers[field.key] = TextEditingController(text: def);
      } else if (field.type == SettingFieldType.toggle) {
        _boolValues[field.key] = def == 'true';
      } else if (field.type == SettingFieldType.dropdown) {
        _dropdownValues[field.key] = def;
      }
    }
    // Apply any already-loaded settings immediately.
    final loaded = ref.read(settingsNotifierProvider).valueOrNull;
    if (loaded != null) _applySettings(loaded);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Applies incoming settings to the form, skipping if user has unsaved edits.
  void _applySettings(Map<String, String> settings) {
    if (_dirty) return;

    // Check whether any value for this section actually changed.
    bool changed = _lastApplied == null;
    if (!changed) {
      for (final f in widget.section.fields) {
        final incoming = settings[f.key] ?? kSettingDefaults[f.key] ?? '';
        if (incoming != (_lastApplied![f.key] ?? kSettingDefaults[f.key] ?? '')) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return;

    _lastApplied = {
      for (final f in widget.section.fields)
        f.key: settings[f.key] ?? kSettingDefaults[f.key] ?? '',
    };

    bool needsSetState = false;
    for (final field in widget.section.fields) {
      final val = _lastApplied![field.key]!;
      if (_isTextField(field.type)) {
        final ctrl = _controllers[field.key];
        if (ctrl != null && ctrl.text != val) ctrl.text = val;
      } else if (field.type == SettingFieldType.toggle) {
        final boolVal = val == 'true';
        if (_boolValues[field.key] != boolVal) {
          _boolValues[field.key] = boolVal;
          needsSetState = true;
        }
      } else if (field.type == SettingFieldType.dropdown) {
        final opts = field.options ?? [];
        final safe = opts.contains(val) ? val : (opts.isEmpty ? '' : opts.first);
        if (_dropdownValues[field.key] != safe) {
          _dropdownValues[field.key] = safe;
          needsSetState = true;
        }
      }
    }
    if (needsSetState && mounted) setState(() {});
  }

  void _resetToDefaults() {
    setState(() {
      for (final field in widget.section.fields) {
        final def = kSettingDefaults[field.key] ?? '';
        if (_isTextField(field.type)) {
          _controllers[field.key]?.text = def;
        } else if (field.type == SettingFieldType.toggle) {
          _boolValues[field.key] = def == 'true';
        } else if (field.type == SettingFieldType.dropdown) {
          _dropdownValues[field.key] = def;
        }
      }
      _dirty = true;
    });
  }

  Map<String, String> _buildPayload() {
    return {
      for (final field in widget.section.fields)
        field.key: switch (field.type) {
          SettingFieldType.toggle =>
            (_boolValues[field.key] ?? false).toString(),
          SettingFieldType.dropdown => _dropdownValues[field.key] ?? '',
          _ => _controllers[field.key]?.text.trim() ?? '',
        },
    };
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsNotifierProvider.notifier)
          .saveSection(_buildPayload());
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
          _lastApplied = _buildPayload();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.section.title} saved'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            width: 320,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            width: 320,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply incoming settings when provider state changes.
    ref.listen<AsyncValue<Map<String, String>>>(
      settingsNotifierProvider,
      (_, next) => next.whenOrNull(data: _applySettings),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.section.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.section.icon,
                    color: widget.section.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.section.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.section.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_dirty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Unsaved',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Fields ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  for (int i = 0; i < widget.section.fields.length; i++) ...[
                    _buildField(widget.section.fields[i]),
                    if (i < widget.section.fields.length - 1)
                      const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),

          // ── Actions ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _resetToDefaults,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset to Default'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: (_dirty && !_saving) ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Changes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.border,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(SettingFieldDef field) {
    return switch (field.type) {
      SettingFieldType.toggle => _buildToggle(field),
      SettingFieldType.dropdown => _buildDropdown(field),
      _ => _buildTextField(field),
    };
  }

  Widget _buildTextField(SettingFieldDef field) {
    return TextFormField(
      controller: _controllers[field.key],
      keyboardType: _keyboardType(field.type),
      inputFormatters: _formatters(field),
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        suffixText: field.unit,
        suffixStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
      onChanged: (_) {
        if (!_dirty) setState(() => _dirty = true);
      },
      validator: (v) => _validate(v, field),
    );
  }

  Widget _buildToggle(SettingFieldDef field) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
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
                  field.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (field.hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    field.hint!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: _boolValues[field.key] ?? false,
            onChanged: (v) => setState(() {
              _boolValues[field.key] = v;
              _dirty = true;
            }),
            activeThumbColor: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(SettingFieldDef field) {
    final opts = field.options ?? [];
    final stored = _dropdownValues[field.key] ?? '';
    final safeValue =
        opts.contains(stored) ? stored : (opts.isEmpty ? null : opts.first);

    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: safeValue,
      decoration: InputDecoration(labelText: field.label),
      items: opts
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _dropdownValues[field.key] = v;
            _dirty = true;
          });
        }
      },
    );
  }

  TextInputType _keyboardType(SettingFieldType t) => switch (t) {
        SettingFieldType.email => TextInputType.emailAddress,
        SettingFieldType.phone => TextInputType.phone,
        SettingFieldType.integer => TextInputType.number,
        SettingFieldType.decimal ||
        SettingFieldType.percent =>
          const TextInputType.numberWithOptions(decimal: true),
        _ => TextInputType.text,
      };

  List<TextInputFormatter> _formatters(SettingFieldDef field) =>
      switch (field.type) {
        SettingFieldType.integer => [FilteringTextInputFormatter.digitsOnly],
        SettingFieldType.decimal ||
        SettingFieldType.percent =>
          [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        _ => [],
      };

  String? _validate(String? v, SettingFieldDef field) {
    final val = v?.trim() ?? '';
    if (field.type == SettingFieldType.email && val.isNotEmpty) {
      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(val)) {
        return 'Enter a valid email address';
      }
    }
    if (field.type == SettingFieldType.integer) {
      if (val.isEmpty) return '${field.label} is required';
      final n = int.tryParse(val);
      if (n == null) return 'Enter a valid whole number';
      if (field.min != null && n < field.min!) {
        return 'Minimum is ${field.min!.toInt()}';
      }
      if (field.max != null && n > field.max!) {
        return 'Maximum is ${field.max!.toInt()}';
      }
    }
    if (field.type == SettingFieldType.decimal ||
        field.type == SettingFieldType.percent) {
      if (val.isEmpty) return '${field.label} is required';
      final n = double.tryParse(val);
      if (n == null) return 'Enter a valid number';
      if (field.min != null && n < field.min!) {
        return 'Minimum is ${field.min}';
      }
      if (field.max != null && n > field.max!) {
        return 'Maximum is ${field.max}';
      }
    }
    return null;
  }
}
