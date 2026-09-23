import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/refund_providers.dart';
import '../../domain/models/refund_issue_category.dart';

/// Two-step dialog for creating a refund request on behalf of a customer.
///
/// Step 1 — Booking lookup: admin searches by booking number, selects a result,
///           sees the booking/payment context, and is warned if an active ticket
///           already exists.
/// Step 2 — Refund form: issue category, description, amount, optional note.
///           Submits via admin_create_refund_request RPC.
class AdminCreateRefundDialog extends ConsumerStatefulWidget {
  const AdminCreateRefundDialog({super.key});

  @override
  ConsumerState<AdminCreateRefundDialog> createState() =>
      _AdminCreateRefundDialogState();
}

class _AdminCreateRefundDialogState
    extends ConsumerState<AdminCreateRefundDialog> {
  // ── Navigation ──────────────────────────────────────────────────────────────
  int _step = 0;

  // ── Step 1 state ────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String? _searchError;
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedBooking; // full booking row from DB
  Map<String, dynamic>? _bookingContext; // {booking, payment_id, payment_method_snapshot, amount_paid_snapshot}
  bool _hasActiveTicker = false;
  bool _loadingContext = false;

  // ── Step 2 state ────────────────────────────────────────────────────────────
  String? _issueCategoryId;
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Step 1: search ──────────────────────────────────────────────────────────

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = [];
      _selectedBooking = null;
      _bookingContext = null;
    });

    try {
      final repo = ref.read(refundRepositoryProvider);
      final results = await repo.searchBookingsForRefund(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchError = results.isEmpty ? 'No bookings found for "$q".' : null;
      });
      if (results.length == 1) await _selectBooking(results.first);
    } catch (e) {
      if (mounted) setState(() => _searchError = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectBooking(Map<String, dynamic> booking) async {
    final bookingId = booking['id'] as String;
    setState(() {
      _selectedBooking = booking;
      _loadingContext = true;
      _searchError = null;
    });

    try {
      final repo = ref.read(refundRepositoryProvider);
      final ctx = await repo.fetchBookingPaymentContext(bookingId);
      final hasTicket = await repo.hasActiveRefundTicket(bookingId);
      if (!mounted) return;
      setState(() {
        _bookingContext = ctx;
        _hasActiveTicker = hasTicket;
      });
    } catch (e) {
      if (mounted) setState(() => _searchError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingContext = false);
    }
  }

  void _continueToForm() {
    if (_bookingContext == null) return;
    // Pre-fill amount with the full amount paid.
    final amountPaid =
        (_bookingContext!['amount_paid_snapshot'] as num).toDouble();
    _amountCtrl.text = amountPaid.toStringAsFixed(2);
    setState(() {
      _step = 1;
      _submitError = null;
    });
  }

  // ── Step 2: submit ──────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_issueCategoryId == null) {
      setState(() => _submitError = 'Please select an issue category.');
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final ctx = _bookingContext!;
      final booking = ctx['booking'] as Map<String, dynamic>;
      final repo = ref.read(refundRepositoryProvider);

      final result = await repo.adminCreateRefundRequest(
        bookingId: booking['id'] as String,
        customerId: booking['customer_id'] as String,
        issueCategoryId: _issueCategoryId!,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        requestedAmount: double.parse(_amountCtrl.text.trim()),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(result['ticket_number'] as String?);
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = _friendlyError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static String _friendlyError(String raw) {
    if (raw.contains('active refund request already exists')) {
      return 'An active refund request already exists for this booking.';
    }
    if (raw.contains('rework')) {
      return 'Warranty rework bookings are not eligible for refunds.';
    }
    if (raw.contains('exceeds amount paid')) {
      return 'Requested amount exceeds the amount paid for this booking.';
    }
    if (raw.contains('Not authorised')) {
      return 'You do not have permission to create refund requests.';
    }
    return raw.replaceFirst(RegExp(r'^Exception: '), '');
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _step == 0 ? _buildStep1() : _buildStep2(),
      ),
    );
  }

  // ── Step 1 ───────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DialogHeader(
            title: 'Create Refund Request',
            subtitle: 'Enter the last 5 digits of the customer\'s booking number.',
          ),
          const SizedBox(height: 20),
          _SearchRow(
            controller: _searchCtrl,
            searching: _searching,
            onSearch: _search,
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 8),
            Text(
              _searchError!,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ],
          if (_searching) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ] else if (_searchResults.isNotEmpty && _selectedBooking == null) ...[
            const SizedBox(height: 12),
            _buildResultsList(),
          ],
          if (_selectedBooking != null) ...[
            const SizedBox(height: 16),
            _loadingContext
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _bookingContext != null
                    ? _BookingContextCard(
                        bookingContext: _bookingContext!,
                        hasActiveTicket: _hasActiveTicker,
                      )
                    : const SizedBox.shrink(),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _bookingContext != null && !_loadingContext
                    ? _continueToForm
                    : null,
                child: const Text('Continue →'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'} — select one',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        ...(_searchResults.map((b) => _BookingResultTile(
              booking: b,
              onTap: () => _selectBooking(b),
            ))),
      ],
    );
  }

  // ── Step 2 ───────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    final ctx = _bookingContext!;
    final booking = ctx['booking'] as Map<String, dynamic>;
    final snapshot = ctx['payment_method_snapshot'] as String;
    final amountPaid = (ctx['amount_paid_snapshot'] as num).toDouble();
    final fmt = NumberFormat('#,##0.00', 'en_IN');

    final categoriesAsync = ref.watch(refundIssueCategoriesProvider);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with back button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _step = 0;
                              _submitError = null;
                            }),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    tooltip: 'Back',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DialogHeader(
                      title: 'Refund Details',
                      subtitle:
                          '#${booking['booking_number'] ?? booking['id']}  ·  '
                          '${_customerLabel(booking)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Payment summary strip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _PillBadge(
                      label: snapshot == 'online'
                          ? 'Online Payment'
                          : 'Cash on Delivery',
                      color: snapshot == 'online'
                          ? AppColors.accent
                          : AppColors.warning,
                    ),
                    const Spacer(),
                    Text(
                      'Amount paid: ₹${fmt.format(amountPaid)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Issue category
              const _FieldLabel('Issue Category *'),
              const SizedBox(height: 6),
              categoriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(
                  'Failed to load categories: $e',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error),
                ),
                data: (cats) => _CategoryDropdown(
                  categories: cats,
                  value: _issueCategoryId,
                  onChanged: (v) => setState(() {
                    _issueCategoryId = v;
                    _submitError = null;
                  }),
                ),
              ),
              const SizedBox(height: 16),
              // Description
              const _FieldLabel('Description'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe the issue and reason for refund…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Requested amount
              const _FieldLabel('Requested Amount *'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                ],
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  border: const OutlineInputBorder(),
                  helperText:
                      'Maximum: ₹${fmt.format(amountPaid)}',
                ),
                validator: (v) {
                  final d = double.tryParse(v?.trim() ?? '');
                  if (d == null || d <= 0) return 'Enter a valid amount';
                  if (d > amountPaid) {
                    return 'Cannot exceed ₹${fmt.format(amountPaid)}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Internal note
              const _FieldLabel('Admin Note (optional — internal only)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText:
                      'Internal context for the team, e.g. "Customer called, agreed to refund"',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _submitError!),
              ],
              const SizedBox(height: 24),
              const Text(
                'Creating this request does NOT approve it or initiate any payment. '
                'The ticket will enter the normal review workflow.',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Refund Request'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _customerLabel(Map<String, dynamic> booking) {
    final c = booking['customers'];
    if (c is Map) {
      final name = c['full_name'] as String? ?? '';
      final phone = c['phone'] as String? ?? '';
      if (name.isNotEmpty) return phone.isNotEmpty ? '$name · $phone' : name;
      if (phone.isNotEmpty) return phone;
    }
    return '—';
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _DialogHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSearch;

  const _SearchRow({
    required this.controller,
    required this.searching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Last 5 digits of booking number, e.g. 1C92F',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: searching ? null : onSearch,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: const Text('Look Up'),
        ),
      ],
    );
  }
}

class _BookingResultTile extends StatefulWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onTap;

  const _BookingResultTile({required this.booking, required this.onTap});

  @override
  State<_BookingResultTile> createState() => _BookingResultTileState();
}

class _BookingResultTileState extends State<_BookingResultTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final c = b['customers'] as Map?;
    final name = c?['full_name'] as String? ?? '—';
    final phone = c?['phone'] as String? ?? '';
    final fmt = NumberFormat('#,##0.00', 'en_IN');
    final amount = (b['total_amount'] as num?)?.toDouble() ?? 0;
    final payMethod = b['payment_method'] as String? ?? 'cash';
    final serviceDate = b['service_date'] as String?;
    final dateFmt = DateFormat('d MMM yy');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primary.withAlpha(10)
                : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withAlpha(80)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${b['booking_number'] ?? b['id']}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$name${phone.isNotEmpty ? ' · $phone' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${fmt.format(amount)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_methodLabel(payMethod)}'
                    '${serviceDate != null ? '  ·  ${dateFmt.format(DateTime.parse(serviceDate))}' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  static String _methodLabel(String m) {
    return switch (m) {
      'cod' => 'COD',
      'online' || 'razorpay' => 'Online',
      _ => 'Cash',
    };
  }
}

class _BookingContextCard extends StatelessWidget {
  final Map<String, dynamic> bookingContext;
  final bool hasActiveTicket;

  const _BookingContextCard({
    required this.bookingContext,
    required this.hasActiveTicket,
  });

  @override
  Widget build(BuildContext context) {
    final booking = bookingContext['booking'] as Map<String, dynamic>;
    final snapshot = bookingContext['payment_method_snapshot'] as String;
    final amountPaid =
        (bookingContext['amount_paid_snapshot'] as num).toDouble();

    final c = booking['customers'] as Map?;
    final name = c?['full_name'] as String? ?? '—';
    final phone = c?['phone'] as String? ?? '';
    final fmt = NumberFormat('#,##0.00', 'en_IN');
    final bookingStatus = booking['status'] as String? ?? '—';
    final payStatus = booking['payment_status'] as String? ?? '—';
    final serviceDate = booking['service_date'] as String?;
    final dateFmt = DateFormat('d MMM yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _BookingRow(
                label: 'Booking',
                value: '#${booking['booking_number'] ?? booking['id']}',
              ),
              const SizedBox(height: 8),
              _BookingRow(
                label: 'Customer',
                value:
                    '$name${phone.isNotEmpty ? ' · $phone' : ''}',
              ),
              if (serviceDate != null) ...[
                const SizedBox(height: 8),
                _BookingRow(
                  label: 'Service date',
                  value: dateFmt.format(DateTime.parse(serviceDate)),
                ),
              ],
              const SizedBox(height: 8),
              _BookingRow(
                label: 'Amount paid',
                value: '₹${fmt.format(amountPaid)}',
              ),
              const SizedBox(height: 8),
              _BookingRow(
                label: 'Payment method',
                value: snapshot == 'online'
                    ? 'Online Payment'
                    : snapshot == 'cod'
                        ? 'Cash on Delivery'
                        : 'Cash',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  _StatusChip(bookingStatus),
                  const SizedBox(width: 8),
                  _StatusChip(payStatus),
                ],
              ),
            ],
          ),
        ),
        if (hasActiveTicket) ...[
          const SizedBox(height: 8),
          _WarningBanner(
            'An active refund ticket already exists for this booking. '
            'Creating another will be blocked by the server.',
          ),
        ],
      ],
    );
  }
}

class _BookingRow extends StatelessWidget {
  final String label;
  final String value;
  const _BookingRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4A5568)),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final List<RefundIssueCategory> categories;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            'Select a category',
            style: theme.inputDecorationTheme.hintStyle,
          ),
          onChanged: onChanged,
          items: categories
              .map((cat) => DropdownMenuItem(
                    value: cat.id,
                    child:
                        Text(cat.label, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
    );
  }
}

class _PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PillBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
