import 'selected_app_file.dart';

/// Esito di una selezione file singola.
sealed class AppFilePickResult {
  const AppFilePickResult();
}

/// L'utente ha annullato il picker (non è un errore tecnico).
final class AppFilePickCancelled extends AppFilePickResult {
  const AppFilePickCancelled();
}

/// Selezione o lettura fallita (messaggio italiano, senza dettagli tecnici).
final class AppFilePickFailure extends AppFilePickResult {
  const AppFilePickFailure(this.message);

  final String message;
}

final class AppFilePickSuccess extends AppFilePickResult {
  const AppFilePickSuccess(this.file);

  final SelectedAppFile file;
}
