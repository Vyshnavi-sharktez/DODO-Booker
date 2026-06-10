import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

const _userTypeOptions = ['customer', 'vendor', 'admin'];
const _notificationTypeOptions = [
  'booking',
  'payment',
  'system',
  'promotion',
  'reminder',
];

class NotificationFormDialog extends StatefulWidget {
  final Future<void> Function({
    required String userType,
    required String userId,
    required String title,
    required String message,
    required String notificationType,
  }) onSave;

  const NotificationFormDialog({super.key, required this.onSave});

  @override
  State<NotificationFormDialog> createState() =>
      _NotificationFormDialogState();
}

class _NotificationFormDialogState extends State<NotificationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userId;
  late final TextEditingController _title;
  late final TextEditingController _message;
  String _userType = 'customer';
  String _notificationType = 'system';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _userId = TextEditingController();
    _title = TextEditingController();
    _message = TextEditingController();
  }

  @override
  void dispose() {
    _userId.dispose();
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        userType: _userType,
        userId: _userId.text.trim(),
        title: _title.text.trim(),
        message: _message.text.trim(),
        notificationType: _notificationType,
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                  const Icon(Icons.add_alert_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'New Notification',
                    style: TextStyle(
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
                      // User Type + Notification Type
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _userType,
                              decoration: const InputDecoration(
                                labelText: 'User Type *',
                                prefixIcon:
                                    Icon(Icons.person_rounded),
                              ),
                              items: _userTypeOptions
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          t[0].toUpperCase() +
                                              t.substring(1),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _userType = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _notificationType,
                              decoration: const InputDecoration(
                                labelText: 'Notification Type *',
                                prefixIcon:
                                    Icon(Icons.category_rounded),
                              ),
                              items: _notificationTypeOptions
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          t[0].toUpperCase() +
                                              t.substring(1),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _notificationType = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // User ID
                      TextFormField(
                        controller: _userId,
                        decoration: const InputDecoration(
                          labelText: 'User ID *',
                          hintText: 'User ID',
                          prefixIcon: Icon(Icons.fingerprint_rounded),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Title
                      TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Title *',
                          hintText: 'Notification Title',
                          prefixIcon: Icon(Icons.title_rounded),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Message
                      TextFormField(
                        controller: _message,
                        decoration: const InputDecoration(
                          labelText: 'Message *',
                          hintText: 'Notification Message',
                          prefixIcon: Icon(Icons.message_rounded),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send Notification'),
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
