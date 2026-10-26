enum RowStatus { valid, updatePending, skipped, invalid }

class BulkRow {
  final int rowNumber;
  final Map<String, String?> raw;
  final RowStatus status;
  final List<String> errors;
  final String? skipReason;
  final String? displayLabel;
  /// ID of the existing DB record, set only for [RowStatus.updatePending] rows.
  final String? existingId;

  const BulkRow({
    required this.rowNumber,
    required this.raw,
    required this.status,
    this.errors = const [],
    this.skipReason,
    this.displayLabel,
    this.existingId,
  });

  BulkRow copyWith({
    RowStatus? status,
    List<String>? errors,
    String? skipReason,
    String? displayLabel,
    String? existingId,
  }) =>
      BulkRow(
        rowNumber: rowNumber,
        raw: raw,
        status: status ?? this.status,
        errors: errors ?? this.errors,
        skipReason: skipReason ?? this.skipReason,
        displayLabel: displayLabel ?? this.displayLabel,
        existingId: existingId ?? this.existingId,
      );
}

class ImportResult {
  final int created;
  final int updated;
  final int skipped;
  final int failed;
  final List<({int row, String reason})> failures;

  const ImportResult({
    required this.created,
    this.updated = 0,
    required this.skipped,
    required this.failed,
    required this.failures,
  });
}
