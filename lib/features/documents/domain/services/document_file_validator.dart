import 'dart:typed_data';

import '../value_objects/document_file_rules.dart';

/// Esito validazione file documento (messaggi italiani, senza dettagli tecnici).
sealed class DocumentFileValidationResult {
  const DocumentFileValidationResult();
}

final class DocumentFileValidationSuccess extends DocumentFileValidationResult {
  const DocumentFileValidationSuccess({
    required this.mimeType,
    required this.canonicalExtension,
    required this.bytes,
  });

  final String mimeType;
  final String canonicalExtension;
  final Uint8List bytes;
}

final class DocumentFileValidationFailure extends DocumentFileValidationResult {
  const DocumentFileValidationFailure(this.message);

  final String message;
}

abstract final class DocumentFileValidator {
  static DocumentFileValidationResult validate({
    required String? fileName,
    required String? declaredMimeType,
    required Uint8List? bytes,
  }) {
    if (bytes == null) {
      return const DocumentFileValidationFailure('Nessun file selezionato.');
    }
    if (bytes.isEmpty) {
      return const DocumentFileValidationFailure(
        'Il file selezionato è vuoto.',
      );
    }
    if (bytes.length > DocumentFileRules.maxSizeBytes) {
      return const DocumentFileValidationFailure(
        'Il file supera il limite di 6 MiB.',
      );
    }

    final extension = _extensionOf(fileName);
    if (extension == null ||
        !DocumentFileRules.allowedExtensions.contains(extension)) {
      return const DocumentFileValidationFailure(
        'Tipo di file non consentito.',
      );
    }

    final mimeFromExtension = DocumentFileRules.mimeForExtension(extension);
    if (mimeFromExtension == null) {
      return const DocumentFileValidationFailure(
        'Tipo di file non consentito.',
      );
    }

    final declared = declaredMimeType?.trim().toLowerCase();
    if (declared != null &&
        declared.isNotEmpty &&
        !DocumentFileRules.allowedMimeTypes.contains(declared)) {
      return const DocumentFileValidationFailure(
        'Tipo di file non consentito.',
      );
    }

    final mimeFromSignature = detectMimeFromSignature(bytes);
    if (mimeFromSignature == null) {
      return const DocumentFileValidationFailure(
        'Il contenuto del file non è coerente con il tipo dichiarato.',
      );
    }

    if (mimeFromSignature != mimeFromExtension) {
      return const DocumentFileValidationFailure(
        'Il contenuto del file non è coerente con il tipo dichiarato.',
      );
    }

    if (declared != null &&
        declared.isNotEmpty &&
        declared != mimeFromSignature) {
      // image/jpg is sometimes reported; normalize jpeg only.
      final normalizedDeclared = declared == 'image/jpg'
          ? 'image/jpeg'
          : declared;
      if (normalizedDeclared != mimeFromSignature) {
        return const DocumentFileValidationFailure(
          'Il contenuto del file non è coerente con il tipo dichiarato.',
        );
      }
    }

    final canonicalExtension = DocumentFileRules.canonicalExtensionForMime(
      mimeFromSignature,
    );
    if (canonicalExtension == null) {
      return const DocumentFileValidationFailure(
        'Tipo di file non consentito.',
      );
    }

    return DocumentFileValidationSuccess(
      mimeType: mimeFromSignature,
      canonicalExtension: canonicalExtension,
      bytes: bytes,
    );
  }

  /// Rileva MIME dalla firma iniziale; `null` se non riconosciuta.
  static String? detectMimeFromSignature(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  static String? _extensionOf(String? fileName) {
    if (fileName == null) {
      return null;
    }
    final trimmed = fileName.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot < 0 || dot == trimmed.length - 1) {
      return null;
    }
    return trimmed.substring(dot + 1).toLowerCase();
  }

  /// Titolo precompilato dal nome file senza estensione.
  static String suggestedTitleFromFileName(String fileName) {
    final trimmed = fileName.trim();
    final dot = trimmed.lastIndexOf('.');
    final base = (dot > 0) ? trimmed.substring(0, dot) : trimmed;
    final title = base.trim();
    if (title.isEmpty) {
      return 'Documento';
    }
    if (title.length <= DocumentFileRules.maxTitleLength) {
      return title;
    }
    return title.substring(0, DocumentFileRules.maxTitleLength);
  }
}
