import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';

class OtpInputField extends StatelessWidget {
  const OtpInputField({
    super.key,
    required this.controller,
    this.validator,
    this.onCompleted,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 12,
        color: AppColors.textPrimary,
      ),
      onChanged: (value) {
        if (value.length == 6) onCompleted?.call();
      },
      onFieldSubmitted: onCompleted != null ? (_) => onCompleted!() : null,
      validator: validator,
      decoration: const InputDecoration(
        counterText: '',
        hintText: '______',
        hintStyle: TextStyle(
          fontSize: 28,
          letterSpacing: 12,
          color: AppColors.textHint,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}
