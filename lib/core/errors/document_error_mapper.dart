import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../errors/exceptions.dart';
import '../errors/failures.dart';

enum DocumentOperation {
  getDocuments,
  uploadDocument,
  createSignedUrl,
  updateTitle,
  setArchived,
}

abstract final class DocumentErrorMapper {
  static Failure mapException(
    Object error, [
    DocumentOperation operation = DocumentOperation.getDocuments,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    if (error is ValidationFailure) {
      return error;
    }
    if (error is Failure) {
      return error;
    }

    if (error is supabase.StorageException) {
      return _mapStorageException(error, operation);
    }
    if (error is supabase.PostgrestException) {
      return _mapPostgrestException(error, operation);
    }

    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('timeout') ||
        text.contains('failed host lookup')) {
      return const NetworkFailure();
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  static Failure _mapStorageException(
    supabase.StorageException error,
    DocumentOperation operation,
  ) {
    final combined = '${error.message} ${error.statusCode ?? ''}'.toLowerCase();

    if (combined.contains('not found') || combined.contains('404')) {
      return const ValidationFailure('Documento non trovato.');
    }
    if (combined.contains('403') ||
        combined.contains('401') ||
        combined.contains('permission') ||
        combined.contains('row-level security') ||
        combined.contains('jwt')) {
      return const AuthFailure(
        'Non hai i permessi per gestire i documenti di questa azienda.',
      );
    }
    if (combined.contains('payload too large') ||
        combined.contains('file size') ||
        combined.contains('exceed')) {
      return const ValidationFailure('Il file supera il limite di 6 MiB.');
    }
    if (combined.contains('mime') || combined.contains('content type')) {
      return const ValidationFailure('Tipo di file non consentito.');
    }
    if (operation == DocumentOperation.uploadDocument) {
      return const NetworkFailure('Caricamento non riuscito. Riprova.');
    }
    if (operation == DocumentOperation.createSignedUrl) {
      return const NetworkFailure(
        'Impossibile generare il collegamento al documento. Riprova.',
      );
    }
    return UnknownFailure(_fallbackMessage(operation));
  }

  static Failure _mapPostgrestException(
    supabase.PostgrestException error,
    DocumentOperation operation,
  ) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final combined = '$message $details $hint';
    final code = error.code ?? '';

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce')) {
      if (operation == DocumentOperation.getDocuments ||
          operation == DocumentOperation.createSignedUrl) {
        return const ValidationFailure('Documento non trovato.');
      }
      return const AuthFailure(
        'Non hai i permessi per modificare questo documento.',
      );
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('violates row-level security') ||
        combined.contains('insufficient permissions')) {
      return const AuthFailure(
        'Non hai i permessi per gestire i documenti di questa azienda.',
      );
    }

    if (combined.contains('documents_title') ||
        (combined.contains('title') && combined.contains('check'))) {
      return const ValidationFailure('Il titolo non è valido.');
    }

    if (combined.contains('documents_mime') ||
        combined.contains('documents_size') ||
        combined.contains('documents_storage_path') ||
        combined.contains('documents_original')) {
      return const ValidationFailure('Tipo di file non consentito.');
    }

    if (operation == DocumentOperation.uploadDocument) {
      return const NetworkFailure(
        'Salvataggio dei dati del documento non riuscito. Riprova.',
      );
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  static String _fallbackMessage(DocumentOperation operation) {
    return switch (operation) {
      DocumentOperation.getDocuments =>
        'Caricamento documenti non riuscito. Riprova.',
      DocumentOperation.uploadDocument =>
        'Caricamento documento non riuscito. Riprova.',
      DocumentOperation.createSignedUrl =>
        'Impossibile generare il collegamento al documento. Riprova.',
      DocumentOperation.updateTitle =>
        'Aggiornamento titolo non riuscito. Riprova.',
      DocumentOperation.setArchived =>
        'Aggiornamento archivio non riuscito. Riprova.',
    };
  }
}
