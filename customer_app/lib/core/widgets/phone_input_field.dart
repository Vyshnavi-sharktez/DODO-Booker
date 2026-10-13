import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneInputField extends StatelessWidget {
  const PhoneInputField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.validator,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.helperText,
    this.decoration,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final InputDecoration? decoration;

  static const String dialCode = '+91';

  static Widget _buildPrefix() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🇮🇳', style: TextStyle(fontSize: 16)),
        SizedBox(width: 5),
        Text(
          '+91',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        SizedBox(width: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = decoration ??
        InputDecoration(
          labelText: labelText,
          hintText: hintText,
          helperText: helperText,
          counterText: '',
        );

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofocus: autofocus,
      enabled: enabled,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      onFieldSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
      validator: validator,
      decoration: base.copyWith(prefix: _buildPrefix()),
    );
  }
}
