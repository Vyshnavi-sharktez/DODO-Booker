import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class SubCategoriesPage extends StatelessWidget {
  const SubCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Sub Categories',
      description: 'Manage sub categories within each category',
      icon: Icons.list_alt_rounded,
    );
  }
}
