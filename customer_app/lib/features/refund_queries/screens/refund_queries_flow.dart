import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/booking_for_refund_model.dart';
import 'booking_selection_screen.dart';
import 'refund_queries_screen.dart';
import 'refund_query_detail_screen.dart';
import 'refund_query_form_screen.dart';

// ── Page-stack entries ─────────────────────────────────────────────────────────

sealed class _Step {
  const _Step();
}

class _StepList extends _Step {
  const _StepList();
}

class _StepSelectBooking extends _Step {
  const _StepSelectBooking();
}

class _StepForm extends _Step {
  const _StepForm(this.booking);
  final BookingForRefundModel booking;
}

class _StepDetail extends _Step {
  const _StepDetail(this.id);
  final String id;
}

// ── Flow widget ────────────────────────────────────────────────────────────────

class RefundQueriesFlow extends StatefulWidget {
  const RefundQueriesFlow({super.key, this.initialRequestId});

  /// When set, the flow opens directly on the detail step for this request ID,
  /// with the list step below so the user can navigate back.
  final String? initialRequestId;

  @override
  State<RefundQueriesFlow> createState() => _RefundQueriesFlowState();
}

class _RefundQueriesFlowState extends State<RefundQueriesFlow> {
  late final List<_Step> _stack = widget.initialRequestId != null
      ? [const _StepList(), _StepDetail(widget.initialRequestId!)]
      : [const _StepList()];

  _Step get _current => _stack.last;
  bool get _canGoBack => _stack.length > 1;

  void _push(_Step step) => setState(() => _stack.add(step));

  void _pop() {
    if (_canGoBack) setState(() => _stack.removeLast());
  }

  String _titleFor(_Step step) => switch (step) {
        _StepList() => '',
        _StepSelectBooking() => 'Select Booking',
        _StepForm() => 'Request Refund',
        _StepDetail() => 'Refund Query',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_canGoBack) _BackRow(title: _titleFor(_current), onBack: _pop),
        Expanded(child: _buildPage()),
      ],
    );
  }

  Widget _buildPage() {
    return switch (_current) {
      _StepList() => KeyedSubtree(
          key: const ValueKey('list'),
          child: RefundQueriesScreen(
            inModal: true,
            onRequestRefund: () => _push(const _StepSelectBooking()),
            onViewQuery: (id) => _push(_StepDetail(id)),
          ),
        ),
      _StepSelectBooking() => KeyedSubtree(
          key: const ValueKey('select'),
          child: BookingSelectionScreen(
            inModal: true,
            onBookingSelected: (b) => _push(_StepForm(b)),
          ),
        ),
      _StepForm(:final booking) => KeyedSubtree(
          key: const ValueKey('form'),
          child: RefundQueryFormScreen(
            booking: booking,
            inModal: true,
            onSubmitSuccess: (id) => setState(() {
              _stack
                ..clear()
                ..add(const _StepList())
                ..add(_StepDetail(id));
            }),
          ),
        ),
      _StepDetail(:final id) => KeyedSubtree(
          key: ValueKey('detail-$id'),
          child: RefundQueryDetailScreen(
            requestId: id,
            inModal: true,
          ),
        ),
    };
  }
}

// ── Back row header ────────────────────────────────────────────────────────────

class _BackRow extends StatelessWidget {
  const _BackRow({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }
}
