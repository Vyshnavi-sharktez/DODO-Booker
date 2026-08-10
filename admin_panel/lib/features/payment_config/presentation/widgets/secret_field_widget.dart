import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

// Write-only secret input. Never pre-populates; shows "Configured / Not set"
// badge based on the [isConfigured] flag from the DB RPC.
class SecretFieldWidget extends StatefulWidget {
  const SecretFieldWidget({
    super.key,
    required this.label,
    required this.isConfigured,
    required this.onSave,
    this.hint,
  });

  final String label;
  final bool isConfigured;
  final Future<void> Function(String value) onSave;
  final String? hint;

  @override
  State<SecretFieldWidget> createState() => _SecretFieldWidgetState();
}

class _SecretFieldWidgetState extends State<SecretFieldWidget> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _hasInput = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(value);
      if (mounted) {
        _controller.clear();
        setState(() {
          _saving = false;
          _hasInput = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.label} updated'),
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
            content: Text('Failed to update ${widget.label}: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(isConfigured: widget.isConfigured),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: widget.isConfigured
                      ? 'Enter new value to replace'
                      : (widget.hint ?? 'Enter ${widget.label}'),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (v) {
                  final hasInput = v.trim().isNotEmpty;
                  if (hasInput != _hasInput) {
                    setState(() => _hasInput = hasInput);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              opacity: _hasInput ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: FilledButton(
                onPressed: (_hasInput && !_saving) ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isConfigured});
  final bool isConfigured;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isConfigured
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isConfigured ? 'Configured' : 'Not set',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isConfigured ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}
