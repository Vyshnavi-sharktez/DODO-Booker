import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_router.dart';
import '../models/booking_for_refund_model.dart';
import '../services/refund_queries_providers.dart';

class RefundQueryFormScreen extends ConsumerStatefulWidget {
  const RefundQueryFormScreen({
    super.key,
    required this.booking,
    this.inModal = false,
    this.onSubmitSuccess,
  });

  final BookingForRefundModel booking;
  final bool inModal;
  final void Function(String id)? onSubmitSuccess;

  @override
  ConsumerState<RefundQueryFormScreen> createState() =>
      _RefundQueryFormScreenState();
}

class _RefundQueryFormScreenState
    extends ConsumerState<RefundQueryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final svc = ref.read(refundQueriesServiceProvider);
      final result = await svc.createRefundRequest(
        bookingId: widget.booking.id,
        issueCategoryId: null,
        description: _descCtrl.text.trim(),
        requestedAmount: widget.booking.totalAmount,
      );

      if (!mounted) return;

      // Invalidate so the list refreshes on return.
      ref.invalidate(myRefundQueriesProvider);
      ref.invalidate(bookingsForRefundProvider);

      final ticketNumber = result['ticket_number'] ?? '';
      final id = result['id'] ?? '';

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Refund query $ticketNumber submitted. '
              "We'll review it shortly.",
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (widget.onSubmitSuccess != null) {
          widget.onSubmitSuccess!(id);
        } else {
          context.go(AppRoutes.refundQueryDetail.replaceFirst(':id', id));
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final formFields = [
      // ── Booking summary banner ───────────────────────────────────────
      Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Booking',
              style: tt.labelSmall?.copyWith(
                color: AppColors.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.booking.serviceName,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _MetaText(widget.booking.displayBookingNumber),
                const _Dot(),
                _MetaText(widget.booking.formattedDate),
                const _Dot(),
                _MetaText(widget.booking.paymentMethodLabel),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Total Paid: ',
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  widget.booking.formattedAmount,
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      const SizedBox(height: 20),

      // ── Description ──────────────────────────────────────────────────
      _SectionHeader('Describe the Issue'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextFormField(
          controller: _descCtrl,
          minLines: 4,
          maxLines: 8,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText:
                'Explain what happened and why you are requesting a refund...',
            hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.border, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.border, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Please describe the issue';
            }
            if (v.trim().length < 20) {
              return 'Please provide at least 20 characters';
            }
            return null;
          },
        ),
      ),

      // ── Refund amount notice ─────────────────────────────────────────
      const SizedBox(height: 20),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The actual refund amount is decided by our team after review.',
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    final submitButton = FilledButton(
      onPressed: _submitting ? null : _submit,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: _submitting
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : const Text('Submit Refund Query'),
    );

    if (widget.inModal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: formFields,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: submitButton,
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(title: const Text('Request Refund')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: formFields,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: submitButton,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 11,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '-',
        style: TextStyle(color: AppColors.textHint, fontSize: 11),
      ),
    );
  }
}
