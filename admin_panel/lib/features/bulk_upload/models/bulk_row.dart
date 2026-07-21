enum RowStatus { valid, skipped, invalid }

class BulkRow {
  final int rowNumber;
  final Map<String, String?> raw;
  final RowStatus status;
  final List<String> errors;
  final String? skipReason;
  final String? displayLabel;

  const BulkRow({
    required this.rowNumber,
    required this.raw,
    required this.status,
    this.errors = const [],
    this.skipReason,
    this.displayLabel,
  });

  BulkRow copyWith({
    RowStatus? status,
    List<String>? errors,
    String? skipReason,
    String? displayLabel,
  }) =>
      BulkRow(
        rowNumber: rowNumber,
        raw: raw,
        status: status ?? this.status,
        errors: errors ?? this.errors,
        skipReason: skipReason ?? this.skipReason,
        displayLabel: displayLabel ?? this.displayLabel,
      );
}

class ImportResult {
  final int created;
  final int skipped;
  final int failed;
  final List<({int row, String reason})> failures;

  const ImportResult({
    required this.created,
    required this.skipped,
    required this.failed,
    required this.failures,
  });
}
