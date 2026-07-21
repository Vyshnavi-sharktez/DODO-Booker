import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../bulk_upload_module.dart';
import '../data/download_helper.dart';
import '../data/excel_utils.dart' as xu;
import '../models/bulk_row.dart';

enum _Step { initial, validating, preview, importing, done }

class BulkUploadDialog extends StatefulWidget {
  final BulkUploadModule module;
  final VoidCallback? onComplete;

  const BulkUploadDialog({super.key, required this.module, this.onComplete});

  static void show(
    BuildContext context,
    BulkUploadModule module, {
    VoidCallback? onComplete,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkUploadDialog(module: module, onComplete: onComplete),
    );
  }

  @override
  State<BulkUploadDialog> createState() => _BulkUploadDialogState();
}

class _BulkUploadDialogState extends State<BulkUploadDialog> {
  _Step _step = _Step.initial;
  List<BulkRow> _rows = [];
  ImportResult? _result;
  String? _error;

  BulkUploadModule get _m => widget.module;

  int get _validCount => _rows.where((r) => r.status == RowStatus.valid).length;
  int get _skipCount => _rows.where((r) => r.status == RowStatus.skipped).length;
  int get _invalidCount =>
      _rows.where((r) => r.status == RowStatus.invalid).length;

  // ── Actions ───────────────────────────────────────────────────────────────────

  Future<void> _downloadTemplate() async {
    try {
      final bytes = xu.generateTemplate(
        columns: _m.templateColumns,
        exampleRows: _m.exampleRows,
        instructions: _m.instructionsText,
      );
      await downloadXlsx(bytes, _m.templateFilename);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Template download failed: $e');
      }
    }
  }

  Future<void> _pickAndValidate() async {
    setState(() => _error = null);
    Uint8List? bytes;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      bytes = result?.files.single.bytes;
    } catch (e) {
      setState(() => _error = 'Could not open file picker: $e');
      return;
    }

    if (bytes == null) return; // user cancelled

    setState(() => _step = _Step.validating);

    String _stage = 'parseXlsx';
    try {
      debugPrint('[BulkUpload] stage=parseXlsx');
      final rawRows = _m.parseXlsx(bytes);
      debugPrint('[BulkUpload] parseXlsx done: ${rawRows.length} rows');

      if (rawRows.isEmpty) {
        setState(() {
          _step = _Step.initial;
          _error = 'No data rows found in the uploaded file.';
        });
        return;
      }

      _stage = 'validateRows';
      debugPrint('[BulkUpload] stage=validateRows');
      final validated = await _m.validateRows(rawRows);
      debugPrint('[BulkUpload] validateRows done: ${validated.length} results');

      setState(() {
        _rows = validated;
        _step = _Step.preview;
      });
    } catch (e, stackTrace) {
      debugPrint('[BulkUpload] ERROR at stage=$_stage: $e\n$stackTrace');
      setState(() {
        _step = _Step.initial;
        _error = 'Validation failed at $_stage: $e';
      });
    }
  }

  Future<void> _confirmImport() async {
    setState(() => _step = _Step.importing);
    try {
      final validRows = _rows.where((r) => r.status == RowStatus.valid).toList();
      final result = await _m.importRows(validRows);
      setState(() {
        _result = result;
        _step = _Step.done;
      });
      widget.onComplete?.call();
    } catch (e) {
      setState(() {
        _step = _Step.preview;
        _error = 'Import failed: $e';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.upload_file_rounded, size: 22, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bulk Upload — ${_m.moduleTitle}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (_step == _Step.initial || _step == _Step.done)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 20),
              style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_step) {
      _Step.initial => _buildInitial(),
      _Step.validating => _buildSpinner('Validating rows…'),
      _Step.preview => _buildPreview(),
      _Step.importing => _buildSpinner('Importing…'),
      _Step.done => _buildDone(),
    };
  }

  // ── Initial step ──────────────────────────────────────────────────────────────

  Widget _buildInitial() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          _Step1Card(onDownload: _downloadTemplate),
          const SizedBox(height: 16),
          _Step2Card(onUpload: _pickAndValidate),
        ],
      ),
    );
  }

  // ── Spinner ───────────────────────────────────────────────────────────────────

  Widget _buildSpinner(String label) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── Preview step ──────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                _ErrorBanner(message: _error!),
                const SizedBox(height: 12),
              ],
              Text(
                '${_rows.length} row${_rows.length == 1 ? '' : 's'} found',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: [
                  _Chip(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    label: '$_validCount will be created',
                  ),
                  if (_skipCount > 0)
                    _Chip(
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      label: '$_skipCount will skip (duplicates)',
                    ),
                  if (_invalidCount > 0)
                    _Chip(
                      icon: Icons.cancel_rounded,
                      color: AppColors.error,
                      label: '$_invalidCount invalid',
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) => _RowTile(row: _rows[i]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() {
                  _step = _Step.initial;
                  _rows = [];
                  _error = null;
                }),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _validCount > 0 ? _confirmImport : null,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text('Import $_validCount Row${_validCount == 1 ? '' : 's'}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Done step ─────────────────────────────────────────────────────────────────

  Widget _buildDone() {
    final r = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                r.failed == 0
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: r.failed == 0 ? AppColors.success : AppColors.warning,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                r.failed == 0 ? 'Import Complete' : 'Import Finished with Errors',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ResultRow(
            icon: Icons.add_circle_rounded,
            color: AppColors.success,
            label: '${r.created} created',
          ),
          if (r.skipped > 0)
            _ResultRow(
              icon: Icons.skip_next_rounded,
              color: AppColors.warning,
              label: '${r.skipped} skipped',
            ),
          if (r.failed > 0) ...[
            _ResultRow(
              icon: Icons.error_rounded,
              color: AppColors.error,
              label: '${r.failed} failed',
            ),
            const SizedBox(height: 12),
            const Text(
              'Failures:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ...r.failures.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Row ${f.row}: ${f.reason}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _Step1Card extends StatelessWidget {
  final VoidCallback onDownload;
  const _Step1Card({required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      step: '1',
      title: 'Download the template',
      subtitle: 'Fill in your data using the provided .xlsx template.',
      action: OutlinedButton.icon(
        onPressed: onDownload,
        icon: const Icon(Icons.download_rounded, size: 16),
        label: const Text('Download Template (.xlsx)'),
      ),
    );
  }
}

class _Step2Card extends StatelessWidget {
  final VoidCallback onUpload;
  const _Step2Card({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      step: '2',
      title: 'Upload your filled file',
      subtitle: 'Select your completed .xlsx file to validate and preview.',
      action: FilledButton.icon(
        onPressed: onUpload,
        icon: const Icon(Icons.upload_rounded, size: 16),
        label: const Text('Upload File (.xlsx)'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  final Widget action;

  const _StepCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(24),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              step,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final BulkRow row;
  const _RowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final (icon, color, detail) = switch (row.status) {
      RowStatus.valid => (
          Icons.check_circle_rounded,
          AppColors.success,
          null,
        ),
      RowStatus.skipped => (
          Icons.warning_amber_rounded,
          AppColors.warning,
          row.skipReason,
        ),
      RowStatus.invalid => (
          Icons.cancel_rounded,
          AppColors.error,
          row.errors.join(', '),
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              'R${row.rowNumber}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.displayLabel != null)
                  Text(
                    row.displayLabel!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(fontSize: 11, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _Chip({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _ResultRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
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
