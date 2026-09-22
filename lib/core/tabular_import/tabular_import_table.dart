/// Tabella normalizzata (intestazioni + righe dati) comune a CSV e XLSX.
class TabularImportTable {
  TabularImportTable({
    required List<String> headers,
    required List<List<String?>> dataRows,
    List<int>? sourceRows,
  }) : headers = List.unmodifiable(headers),
       dataRows = List.unmodifiable(dataRows.map(List<String?>.unmodifiable)),
       sourceRows = List.unmodifiable(
         sourceRows ??
             List<int>.generate(dataRows.length, (index) => index + 2),
       ) {
    if (this.sourceRows.length != this.dataRows.length) {
      throw ArgumentError.value(
        sourceRows,
        'sourceRows',
        'Must have one source row for each data row.',
      );
    }
  }

  final List<String> headers;
  final List<List<String?>> dataRows;
  final List<int> sourceRows;

  int get rowCount => dataRows.length;

  @override
  String toString() =>
      'TabularImportTable(headerCount: ${headers.length}, rowCount: $rowCount)';
}
