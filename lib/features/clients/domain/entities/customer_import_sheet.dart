class CustomerImportSheet {
  const CustomerImportSheet({required this.name, required this.rowCount});

  final String name;
  final int rowCount;

  @override
  String toString() => 'CustomerImportSheet(rowCount: $rowCount)';
}
