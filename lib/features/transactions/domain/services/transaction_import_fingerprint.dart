import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Impronte SHA-256 usate per la deduplica dell'import movimenti.
abstract final class TransactionImportFingerprint {
  /// Descrizione normalizzata: minuscolo, spazi compattati, senza estremi.
  static String normalizeDescription(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Impronta della riga: `date|kind|amount|normalizedDescription|reference?`.
  static String rowFingerprint({
    required String occurredOn,
    required String kind,
    required String amount,
    required String description,
    String? reference,
  }) {
    final canonical = [
      occurredOn,
      kind,
      amount,
      normalizeDescription(description),
      if (reference != null && reference.trim().isNotEmpty)
        normalizeDescription(reference),
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Chiave di confronto con i movimenti già presenti: senza riferimento.
  static String existingMatchKey({
    required String occurredOn,
    required String kind,
    required String amount,
    required String description,
  }) {
    final canonical = [
      occurredOn,
      kind,
      amount,
      normalizeDescription(description),
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Impronta dei byte grezzi del file: stesso file = stessa impronta.
  static String fileFingerprint(Uint8List bytes) =>
      sha256.convert(bytes).toString();
}
