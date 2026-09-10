import 'package:flutter/material.dart';
import '../../catalog/services/catalog_service.dart';
import '../widgets/vendor_custom_service_sheet.dart';

/// Opens the vendor custom service sheet by fetching the model first.
/// Analogous to [openCatalogNode] for deep-link / notification tap use cases.
Future<void> openCustomServiceQA(
    BuildContext context, String customServiceId) async {
  final service = await CatalogService().fetchCustomServiceById(customServiceId);
  if (service == null || !context.mounted) return;
  VendorCustomServiceSheet.show(context, service);
}
