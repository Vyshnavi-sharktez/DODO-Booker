import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';

import '../../application/call_monitoring_providers.dart';
import '../../domain/models/admin_call_session.dart';
import '../widgets/call_session_details_dialog.dart';

class CallSessionsPage extends ConsumerStatefulWidget {
  const CallSessionsPage({super.key});

  @override
  ConsumerState<CallSessionsPage> createState() => _CallSessionsPageState();
}

class _CallSessionsPageState extends ConsumerState<CallSessionsPage> {
  String _searchQuery = '';
  String _selectedStatus = 'All';
  String _selectedRole = 'All';
  String _selectedDateRange = 'All Time';

  List<AdminCallSession> _applyFilters(List<AdminCallSession> allSessions) {
    return allSessions.where((s) {
      // 1. Search Query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchId = s.id.toLowerCase().contains(query);
        final matchBooking = s.displayBookingNumber.toLowerCase().contains(query);
        final matchVirtual = s.virtualNumber.toLowerCase().contains(query);
        final matchCaller = s.callerId.toLowerCase().contains(query);
        final matchCallee = s.calleeId.toLowerCase().contains(query);
        if (!matchId && !matchBooking && !matchVirtual && !matchCaller && !matchCallee) {
          return false;
        }
      }

      // 2. Status Filter
      if (_selectedStatus != 'All') {
        if (s.status.toLowerCase() != _selectedStatus.toLowerCase()) {
          return false;
        }
      }

      // 3. Caller Role Filter
      if (_selectedRole != 'All') {
        if (s.callerRole.toLowerCase() != _selectedRole.toLowerCase()) {
          return false;
        }
      }

      // 4. Date Range Filter
      if (_selectedDateRange != 'All Time') {
        final now = DateTime.now();
        final date = s.initiatedAt;
        if (_selectedDateRange == 'Today') {
          if (date.year != now.year || date.month != now.month || date.day != now.day) {
            return false;
          }
        } else if (_selectedDateRange == 'Last 7 Days') {
          if (now.difference(date).inDays > 7) return false;
        } else if (_selectedDateRange == 'Last 30 Days') {
          if (now.difference(date).inDays > 30) return false;
        }
      }

      return true;
    }).toList();
  }

  void _exportCsv(List<AdminCallSession> sessions) {
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No call sessions to export.')),
      );
      return;
    }

    final StringBuffer csv = StringBuffer();
    csv.writeln('Session ID,Booking Number,Caller Role,Virtual Number,Status,Initiated At,Ended At,Duration (Seconds)');

    for (final s in sessions) {
      csv.writeln(
        '"${s.id}","${s.displayBookingNumber}","${s.callerRole}","${s.virtualNumber}","${s.status}","${s.initiatedAt.toIso8601String()}","${s.endedAt?.toIso8601String() ?? ''}","${s.durationSeconds}"',
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${sessions.length} call session records to CSV.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'connected':
        return Colors.green;
      case 'ringing':
        return Colors.blue;
      case 'ended':
        return AppColors.primary;
      case 'initiated':
        return Colors.orange;
      case 'missed':
        return Colors.amber.shade800;
      case 'failed':
        return Colors.red;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncSessions = ref.watch(adminCallSessionsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header & Actions (Responsive Wrap)
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Call Sessions Monitoring',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Real-time tracking and metrics for DODO Virtual Voice Bridge calls',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(adminCallSessionsStreamProvider),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Refresh'),
                    ),
                    asyncSessions.when(
                      data: (all) => ElevatedButton.icon(
                        onPressed: () => _exportCsv(_applyFilters(all)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Export CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            asyncSessions.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, stack) => Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading call sessions: $err', style: const TextStyle(color: Colors.red)),
                ),
              ),
              data: (allSessions) {
                final filtered = _applyFilters(allSessions);

                // KPI Calculations
                final totalCount = allSessions.length;
                final initiatedCount = allSessions.where((s) => s.isInitiated).length;
                final ringingCount = allSessions.where((s) => s.isRinging).length;
                final connectedCount = allSessions.where((s) => s.isConnected).length;
                final endedCount = allSessions.where((s) => s.isEnded).length;
                final missedCount = allSessions.where((s) => s.isMissed).length;
                final failedCount = allSessions.where((s) => s.isFailed).length;

                final totalDurationSecs = allSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
                final avgDurationSecs = totalCount > 0 ? (totalDurationSecs / totalCount).round() : 0;
                final avgMinutes = (avgDurationSecs ~/ 60).toString().padLeft(2, '0');
                final avgSeconds = (avgDurationSecs % 60).toString().padLeft(2, '0');
                final avgFormatted = '$avgMinutes:$avgSeconds';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI Cards Grid (Responsive Wrap)
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _KpiCard(
                          title: 'Total Calls',
                          value: '$totalCount',
                          icon: Icons.phone_in_talk_rounded,
                          color: AppColors.primary,
                        ),
                        _KpiCard(
                          title: 'Ringing / Active',
                          value: '${initiatedCount + ringingCount}',
                          icon: Icons.ring_volume_rounded,
                          color: Colors.blue,
                        ),
                        _KpiCard(
                          title: 'Connected',
                          value: '$connectedCount',
                          icon: Icons.call_rounded,
                          color: Colors.green,
                        ),
                        _KpiCard(
                          title: 'Ended Calls',
                          value: '$endedCount',
                          icon: Icons.call_end_rounded,
                          color: AppColors.primary,
                        ),
                        _KpiCard(
                          title: 'Missed / Failed',
                          value: '${missedCount + failedCount}',
                          icon: Icons.phone_disabled_rounded,
                          color: Colors.red,
                        ),
                        _KpiCard(
                          title: 'Avg Duration',
                          value: avgFormatted,
                          icon: Icons.timer_rounded,
                          color: Colors.purple,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Filters Card (Responsive Wrap)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 260,
                              child: TextField(
                                onChanged: (v) => setState(() => _searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: 'Search booking / virtual num...',
                                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            DropdownButton<String>(
                              value: _selectedStatus,
                              underline: const SizedBox(),
                              items: ['All', 'initiated', 'ringing', 'connected', 'ended', 'missed', 'failed']
                                  .map((s) => DropdownMenuItem(value: s, child: Text('Status: $s')))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedStatus = v ?? 'All'),
                            ),
                            DropdownButton<String>(
                              value: _selectedRole,
                              underline: const SizedBox(),
                              items: ['All', 'customer', 'vendor']
                                  .map((r) => DropdownMenuItem(value: r, child: Text('Caller: $r')))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedRole = v ?? 'All'),
                            ),
                            DropdownButton<String>(
                              value: _selectedDateRange,
                              underline: const SizedBox(),
                              items: ['All Time', 'Today', 'Last 7 Days', 'Last 30 Days']
                                  .map((d) => DropdownMenuItem(value: d, child: Text('Date: $d')))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedDateRange = v ?? 'All Time'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Data Table Card
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Session ID', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Booking Number', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Caller Role', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Virtual Number', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Initiated At', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Duration', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: filtered.map((session) {
                            final statusCol = _statusColor(session.status);

                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    session.id.length > 12
                                        ? '${session.id.substring(0, 12)}...'
                                        : session.id,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    session.displayBookingNumber,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ),
                                DataCell(
                                  Chip(
                                    label: Text(
                                      session.callerRole.toUpperCase(),
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                    backgroundColor: session.callerRole == 'customer'
                                        ? Colors.blue.shade50
                                        : Colors.purple.shade50,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    session.virtualNumber,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusCol.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: statusCol.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      session.status.toUpperCase(),
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusCol),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    session.initiatedAt.toLocal().toString().split('.').first,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    session.durationFormatted,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.visibility_rounded, size: 18, color: AppColors.primary),
                                    tooltip: 'View Session Details',
                                    onPressed: () => CallSessionDetailsDialog.show(context, session),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
