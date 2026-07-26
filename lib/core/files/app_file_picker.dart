import 'app_file_pick_result.dart';

/// Astrazione applicativa per la selezione di un singolo file.
abstract class AppFilePicker {
  /// CSV / XLSX per import clienti.
  Future<AppFilePickResult> pickCustomerImportFile();

  /// PDF / immagini per upload documenti.
  Future<AppFilePickResult> pickDocumentUploadFile();
}
