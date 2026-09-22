class TransactionImportResult {
  TransactionImportResult({
    required this.batchId,
    required this.importedCount,
    required this.skippedInvalidCount,
    required this.skippedDuplicateCount,
    required List<String> transactionIds,
  }) : transactionIds = List.unmodifiable(transactionIds);

  final String batchId;
  final int importedCount;
  final int skippedInvalidCount;
  final int skippedDuplicateCount;
  final List<String> transactionIds;

  @override
  String toString() {
    return 'TransactionImportResult(batchId: $batchId, '
        'importedCount: $importedCount, '
        'skippedInvalidCount: $skippedInvalidCount, '
        'skippedDuplicateCount: $skippedDuplicateCount, '
        'transactionIdCount: ${transactionIds.length})';
  }
}
