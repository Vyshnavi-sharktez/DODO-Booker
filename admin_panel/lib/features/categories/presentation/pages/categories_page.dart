import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Categories',
      description: 'Manage service categories',
      icon: Icons.category_rounded,
    );
  }
}
