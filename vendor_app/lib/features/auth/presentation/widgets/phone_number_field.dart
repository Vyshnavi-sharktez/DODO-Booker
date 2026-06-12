import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';

class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.countryCode = '+91',
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String countryCode;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      maxLength: 10,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onFieldSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
      validator: validator,
      decoration: InputDecoration(
        labelText: 'Mobile Number',
        hintText: 'Enter mobile number',
        counterText: '',
        prefix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              countryCode,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 18,
              color: AppColors.border,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
