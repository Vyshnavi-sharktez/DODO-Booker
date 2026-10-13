import 'package:flutter/material.dart';
import '../../../../core/widgets/phone_input_field.dart';

class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return PhoneInputField(
      controller: controller,
      labelText: 'Mobile Number',
      hintText: 'Enter mobile number',
      validator: validator,
      onSubmitted: onSubmitted,
    );
  }
}
