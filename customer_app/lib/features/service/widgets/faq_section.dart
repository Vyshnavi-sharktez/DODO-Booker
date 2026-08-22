import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/faq_model.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../profile/services/profile_providers.dart';

class FaqSection extends StatelessWidget {
  final List<FaqModel> faqs;

  const FaqSection({super.key, required this.faqs});

  @override
  Widget build(BuildContext context) {
    if (faqs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: faqs.map((faq) => _FaqItem(faq: faq)).toList(),
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.faq});
  final FaqModel faq;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, thickness: 0.8, color: AppColors.border),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          mouseCursor: SystemMouseCursors.click,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.faq.question,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              widget.faq.answer,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Ask a question link ───────────────────────────────────────────────────────

/// Renders "Have a question? Ask us →" in gold. Tapping it gates auth, then
/// opens [_QuestionSheet] which submits to the customer_questions table.
class AskQuestionLink extends ConsumerWidget {
  const AskQuestionLink({super.key, required this.serviceId, this.parentId});
  final String serviceId;
  final String? parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onAsk(context, ref),
        child: const Text(
          'Have a question? Ask us →',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _onAsk(BuildContext context, WidgetRef ref) async {
    final ok = await requireAuth(context, ref);
    if (!ok || !context.mounted) return;

    final profile = await ref.read(profileProvider.future);
    if (!context.mounted) return;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuestionSheet(
        onSubmit: (question) => ref.read(catalogServiceProvider).submitQuestion(
              serviceId: serviceId,
              parentNodeId: parentId,
              customerId: profile.id,
              customerName:
                  profile.fullName.isNotEmpty ? profile.fullName : null,
              customerPhone:
                  profile.mobileNumber.isNotEmpty ? profile.mobileNumber : null,
              question: question,
            ),
      ),
    );

    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Question submitted! We'll notify you when it's answered."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

class _QuestionSheet extends StatefulWidget {
  const _QuestionSheet({required this.onSubmit});
  final Future<void> Function(String question) onSubmit;

  @override
  State<_QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<_QuestionSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ask a Question',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text(
            'Our team will review and answer your question.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Type your question here…',
              hintStyle: const TextStyle(color: AppColors.textHint),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.gold),
              ),
              contentPadding: const EdgeInsets.all(12),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Question',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() => _error = 'Please enter your question.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onSubmit(q);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to submit. Please try again.';
        });
      }
    }
  }
}
