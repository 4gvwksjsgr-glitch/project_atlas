import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../errors/exceptions.dart';
import '../errors/failures.dart';

enum DocumentOperation {
  getDocuments,
  uploadDocument,
  createSignedUrl,
  updateTitle,
  setArchived,
  updateLinks,
  deleteDocument,
  deleteDocumentStorage,
  deleteDocumentMetadata,
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
    if (error is DocumentStorageDeleteNoOpException) {
      return DocumentStorageDeleteNoOpFailure(error.message);
    }
    if (error is DocumentMetadataDeleteNoOpException) {
      return DocumentMetadataDeleteNoOpFailure(error.message);
    }
    if (error is IncompleteDocumentDeletionFailure) {
      return error;
    }
    if (error is DocumentStorageDeleteNoOpFailure) {
      return error;
    }
    if (error is DocumentMetadataDeleteNoOpFailure) {
      return error;
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
      if (operation == DocumentOperation.deleteDocumentStorage ||
          operation == DocumentOperation.deleteDocument) {
        return const ValidationFailure('Il documento risulta già eliminato.');
      }
      return const ValidationFailure('Documento non trovato.');
    }
    if (combined.contains('403') ||
        combined.contains('401') ||
        combined.contains('permission') ||
        combined.contains('row-level security') ||
        combined.contains('jwt')) {
      if (operation == DocumentOperation.deleteDocumentStorage ||
          operation == DocumentOperation.deleteDocument ||
          operation == DocumentOperation.deleteDocumentMetadata) {
        return const DocumentMetadataDeleteNoOpFailure();
      }
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
    if (operation == DocumentOperation.deleteDocumentStorage ||
        operation == DocumentOperation.deleteDocument) {
      return const DocumentStorageDeleteNoOpFailure();
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
      if (operation == DocumentOperation.deleteDocument) {
        return const ValidationFailure('Il documento risulta già eliminato.');
      }
      if (operation == DocumentOperation.getDocuments ||
          operation == DocumentOperation.createSignedUrl) {
        return const ValidationFailure('Documento non trovato.');
      }
      if (operation == DocumentOperation.updateLinks) {
        return const AuthFailure(
          'Non hai i permessi per modificare i collegamenti di questo documento.',
        );
      }
      if (operation == DocumentOperation.deleteDocumentMetadata) {
        return const IncompleteDocumentDeletionFailure();
      }
      return const AuthFailure(
        'Non hai i permessi per modificare questo documento.',
      );
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('violates row-level security') ||
        combined.contains('insufficient permissions')) {
      if (operation == DocumentOperation.deleteDocument ||
          operation == DocumentOperation.deleteDocumentMetadata ||
          operation == DocumentOperation.deleteDocumentStorage) {
        return const DocumentMetadataDeleteNoOpFailure();
      }
      return const AuthFailure(
        'Non hai i permessi per gestire i documenti di questa azienda.',
      );
    }

    if (combined.contains('documents_company_client_fkey') ||
        (combined.contains('client') &&
            (combined.contains('foreign key') ||
                combined.contains('violates foreign key')))) {
      return const ValidationFailure(
        'Cliente non trovato o appartenente a un\'altra azienda.',
      );
    }

    if (combined.contains('documents_company_transaction_fkey') ||
        (combined.contains('transaction') &&
            (combined.contains('foreign key') ||
                combined.contains('violates foreign key')))) {
      return const ValidationFailure(
        'Movimento non trovato o appartenente a un\'altra azienda.',
      );
    }

    if (combined.contains('foreign key') ||
        combined.contains('violates foreign key')) {
      return const ValidationFailure(
        'Collegamento non più valido. Aggiorna la selezione e riprova.',
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

    if (operation == DocumentOperation.deleteDocumentMetadata ||
        operation == DocumentOperation.deleteDocument) {
      return const IncompleteDocumentDeletionFailure();
    }

    if (operation == DocumentOperation.updateLinks) {
      return const UnknownFailure(
        'Aggiornamento collegamenti non riuscito. Riprova.',
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
      DocumentOperation.updateLinks =>
        'Aggiornamento collegamenti non riuscito. Riprova.',
      DocumentOperation.deleteDocumentStorage =>
        'Non è stato possibile eliminare il file.',
      DocumentOperation.deleteDocumentMetadata =>
        'Il file è stato rimosso, ma i dati del documento non sono stati '
            'eliminati. Riprova.',
      DocumentOperation.deleteDocument =>
        'Eliminazione documento non riuscita. Riprova.',
    };
  }
}
