class CustomerImportResult {
  CustomerImportResult({
    required this.insertedCount,
    required this.skippedDuplicateCount,
    required List<int> skippedSourceRows,
  }) : skippedSourceRows = List.unmodifiable(skippedSourceRows);

  final int insertedCount;
  final int skippedDuplicateCount;
  final List<int> skippedSourceRows;

  @override
  String toString() {
    return 'CustomerImportResult(insertedCount: $insertedCount, '
        'skippedDuplicateCount: $skippedDuplicateCount, '
        'skippedSourceRowCount: ${skippedSourceRows.length})';
  }
}
