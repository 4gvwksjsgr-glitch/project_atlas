import 'app_file_pick_result.dart';

/// Formato tabellare scelto prima del picker OS (richiesto su Android).
enum TabularImportFileFormat { csv, xlsx }

/// Astrazione applicativa per la selezione di un singolo file.
abstract class AppFilePicker {
  /// CSV / XLSX per import clienti.
  ///
  /// Su Android [format] deve essere esplicito (un MIME per Intent).
  /// Su altre piattaforme [format] può restare `null` (filtro combinato).
  Future<AppFilePickResult> pickCustomerImportFile({
    TabularImportFileFormat? format,
  });

  /// CSV / XLSX per import movimenti.
  ///
  /// Su Android [format] deve essere esplicito (un MIME per Intent).
  /// Su altre piattaforme [format] può restare `null` (filtro combinato).
  Future<AppFilePickResult> pickTransactionImportFile({
    TabularImportFileFormat? format,
  });

  /// PDF / immagini per upload documenti.
  Future<AppFilePickResult> pickDocumentUploadFile();
}
