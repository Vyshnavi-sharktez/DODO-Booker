import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../models/service_model.dart';
import '../modals/service_detail_modal.dart';

/// Opens service details as a floating dialog on desktop (≥768px) and as a
/// full-screen push route on mobile. Call this instead of
/// `context.push('/service-detail/...')` at every tap site.
void openServiceDetail(BuildContext context, ServiceModel service) {
  if (MediaQuery.of(context).size.width >= 768) {
    ServiceDetailModal.show(context, service);
  } else {
    context.push('/service-detail/${service.id}', extra: service);
  }
}
