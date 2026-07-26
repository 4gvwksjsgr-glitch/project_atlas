import 'dart:typed_data';

/// File selezionato dall'utente, indipendente da XFile / file_selector.
class SelectedAppFile {
  const SelectedAppFile({
    required this.name,
    required this.extension,
    required this.mimeType,
    required this.size,
    required this.bytes,
  });

  /// Nome file originale (con estensione).
  final String name;

  /// Estensione senza punto, lowercase (può essere vuota se assente).
  final String extension;

  /// MIME dichiarato dal picker, se disponibile.
  final String? mimeType;

  /// Dimensione definitiva = `bytes.length`.
  final int size;

  final Uint8List bytes;
}
