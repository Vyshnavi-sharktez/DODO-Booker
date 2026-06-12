import 'package:flutter/material.dart';

class AppPlaceholder extends StatelessWidget {
  final String label;

  const AppPlaceholder({super.key, this.label = 'Placeholder'});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(label));
  }
}
