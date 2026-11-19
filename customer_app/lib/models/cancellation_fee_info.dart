class CancellationFeeInfo {
  final double feeAmount;
  final double refundAmount;
  final bool isCod;
  final String reasonMessage;

  const CancellationFeeInfo({
    required this.feeAmount,
    required this.refundAmount,
    required this.isCod,
    this.reasonMessage = 'Free cancellation',
  });

  bool get hasFee => feeAmount > 0;

  factory CancellationFeeInfo.free() => const CancellationFeeInfo(
        feeAmount: 0,
        refundAmount: 0,
        isCod: false,
        reasonMessage: 'Free cancellation',
      );

  factory CancellationFeeInfo.fromJson(Map<String, dynamic> json) =>
      CancellationFeeInfo(
        feeAmount: (json['fee_amount'] as num?)?.toDouble() ?? 0,
        refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
        isCod: (json['is_cod'] as bool?) ?? false,
        reasonMessage:
            (json['reason_message'] as String?) ?? 'Free cancellation',
      );
}
