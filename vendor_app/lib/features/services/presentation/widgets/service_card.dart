import 'package:flutter/material.dart';
import '../../domain/models/assigned_service.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service});

  final AssignedService service;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
