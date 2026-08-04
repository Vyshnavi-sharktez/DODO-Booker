import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/gps_audit_providers.dart';
import '../../domain/models/gps_cancellation_audit.dart';

class GpsAuditDetailsDialog extends ConsumerStatefulWidget {
  const GpsAuditDetailsDialog({
    super.key,
    required this.audit,
  });

  final GpsCancellationAudit audit;

  @override
  ConsumerState<GpsAuditDetailsDialog> createState() =>
      _GpsAuditDetailsDialogState();
}

class _GpsAuditDetailsDialogState
    extends ConsumerState<GpsAuditDetailsDialog> {
  late String _selectedStatus;
  bool _isSaving = false;

  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm:ss a');

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.audit.auditStatus;
  }

  Future<void> _saveStatus() async {
    if (_selectedStatus == widget.audit.auditStatus) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(gpsAuditNotifierProvider.notifier)
          .updateAuditStatus(auditId: widget.audit.id, newStatus: _selectedStatus);

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audit status updated successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audit = widget.audit;
    final bookingRef = audit.bookingNumber != null && audit.bookingNumber!.isNotEmpty
        ? '#${audit.bookingNumber}'
        : '#${audit.bookingId.length > 8 ? audit.bookingId.substring(0, 8).toUpperCase() : audit.bookingId}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GPS Cancellation Evidence — $bookingRef',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Audited on ${_dateFmt.format(audit.auditedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColors.border),
              const SizedBox(height: 14),

              // Scrollable Details Body
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Responsive Metric Cards Grid
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 500;
                          if (isNarrow) {
                            return Column(
                              children: [
                                _MetricCard(
                                  label: 'Minimum Distance',
                                  value:
                                      '${audit.minDistanceMeters.toStringAsFixed(1)} m',
                                  icon: Icons.straighten_rounded,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 8),
                                _MetricCard(
                                  label: 'Configured Radius',
                                  value:
                                      '${audit.geofenceRadiusMeters.toStringAsFixed(0)} m',
                                  icon: Icons.radar_rounded,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                _MetricCard(
                                  label: 'Geofence Result',
                                  value: 'Inside Geofence',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: AppColors.warning,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  label: 'Minimum Distance',
                                  value:
                                      '${audit.minDistanceMeters.toStringAsFixed(1)} m',
                                  icon: Icons.straighten_rounded,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  label: 'Configured Radius',
                                  value:
                                      '${audit.geofenceRadiusMeters.toStringAsFixed(0)} m',
                                  icon: Icons.radar_rounded,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  label: 'Geofence Result',
                                  value: 'Inside Geofence',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Location Evidence Section
                      const Text(
                        'GPS Location Coordinates & Timestamp',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _DetailRow(
                              label: 'Booking Location:',
                              value:
                                  '${audit.bookingLatitude.toStringAsFixed(6)}, ${audit.bookingLongitude.toStringAsFixed(6)}',
                              icon: Icons.home_rounded,
                            ),
                            const Divider(color: AppColors.border, height: 16),
                            _DetailRow(
                              label: 'Nearest Vendor GPS:',
                              value:
                                  '${audit.nearestLatitude.toStringAsFixed(6)}, ${audit.nearestLongitude.toStringAsFixed(6)}',
                              icon: Icons.location_on_rounded,
                            ),
                            const Divider(color: AppColors.border, height: 16),
                            _DetailRow(
                              label: 'GPS Fix Accuracy:',
                              value: audit.nearestAccuracy != null
                                  ? '±${audit.nearestAccuracy!.toStringAsFixed(1)} meters'
                                  : 'Not recorded',
                              icon: Icons.gps_fixed_rounded,
                            ),
                            const Divider(color: AppColors.border, height: 16),
                            _DetailRow(
                              label: 'Recorded Timestamp:',
                              value: _dateFmt.format(audit.nearestRecordedAt),
                              icon: Icons.access_time_rounded,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Booking Context Section
                      const Text(
                        'Booking & Parties Context',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _DetailRow(
                              label: 'Customer:',
                              value:
                                  '${audit.customerName ?? 'Customer'} (${audit.customerPhone ?? '—'})',
                              icon: Icons.person_rounded,
                            ),
                            const Divider(color: AppColors.border, height: 16),
                            _DetailRow(
                              label: 'Vendor:',
                              value:
                                  '${audit.vendorBusinessName ?? 'Vendor'} (${audit.vendorPhone ?? '—'})',
                              icon: Icons.storefront_rounded,
                            ),
                            const Divider(color: AppColors.border, height: 16),
                            _DetailRow(
                              label: 'Customer Reason:',
                              value: audit.cancellationReason?.isNotEmpty == true
                                  ? audit.cancellationReason!
                                  : 'Unspecified',
                              icon: Icons.chat_bubble_outline_rounded,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Update Status Panel
                      const Text(
                        'Update Audit Decision',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Decision:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedStatus,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'potential_false_cancellation',
                                  child: Text('Potential False Cancellation',
                                      overflow: TextOverflow.ellipsis),
                                ),
                                DropdownMenuItem(
                                  value: 'verified_false_cancellation',
                                  child: Text('Verified False Cancellation',
                                      overflow: TextOverflow.ellipsis),
                                ),
                                DropdownMenuItem(
                                  value: 'verified_valid_cancellation',
                                  child: Text('Verified Valid Cancellation',
                                      overflow: TextOverflow.ellipsis),
                                ),
                                DropdownMenuItem(
                                  value: 'dismissed',
                                  child: Text('Dismissed',
                                      overflow: TextOverflow.ellipsis),
                                ),
                                DropdownMenuItem(
                                  value: 'pending_review',
                                  child: Text('Pending Review',
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedStatus = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Actions Footer
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed:
                        _isSaving || _selectedStatus == widget.audit.auditStatus
                            ? null
                            : _saveStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 44),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save Decision'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
