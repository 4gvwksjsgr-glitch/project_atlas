/// Foglio disponibile in una sorgente tabellare (per XLSX multi-foglio).
class TabularImportSheet {
  const TabularImportSheet({required this.name, required this.rowCount});

  final String name;
  final int rowCount;

  @override
  String toString() => 'TabularImportSheet(rowCount: $rowCount)';
}
