import 'calendar_date.dart';
import '../entities/cash_transaction.dart';

/// Filtri AND per la lista movimenti (tutti i campi opzionali).
///
/// Nessuna paginazione: la query restituisce l'intero risultato filtrato.
class TransactionFilters {
  const TransactionFilters({
    this.fromDate,
    this.toDate,
    this.kind,
    this.clientId,
    this.descriptionQuery = '',
  });

  /// Inclusivo (`occurred_on >= fromDate`).
  final DateTime? fromDate;

  /// Inclusivo (`occurred_on <= toDate`).
  final DateTime? toDate;

  /// `null` = tutti i tipi.
  final TransactionKind? kind;

  /// `null` / vuoto = tutti i clienti.
  final String? clientId;

  /// Ricerca case-insensitive su `description` (trim lato query).
  final String descriptionQuery;

  bool get hasActiveFilters {
    return fromDate != null ||
        toDate != null ||
        kind != null ||
        (clientId != null && clientId!.trim().isNotEmpty) ||
        descriptionQuery.trim().isNotEmpty;
  }

  /// Errore di validazione, oppure `null` se i filtri sono coerenti.
  String? get validationError {
    if (fromDate == null || toDate == null) {
      return null;
    }
    final from = CalendarDate.dateOnly(fromDate!);
    final to = CalendarDate.dateOnly(toDate!);
    if (from.isAfter(to)) {
      return 'La data iniziale non può essere successiva alla data finale.';
    }
    return null;
  }

  TransactionFilters clear() => const TransactionFilters();

  TransactionFilters copyWith({
    DateTime? fromDate,
    DateTime? toDate,
    TransactionKind? kind,
    String? clientId,
    String? descriptionQuery,
    bool clearFromDate = false,
    bool clearToDate = false,
    bool clearKind = false,
    bool clearClientId = false,
  }) {
    return TransactionFilters(
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      kind: clearKind ? null : (kind ?? this.kind),
      clientId: clearClientId ? null : (clientId ?? this.clientId),
      descriptionQuery: descriptionQuery ?? this.descriptionQuery,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TransactionFilters &&
        other.fromDate == fromDate &&
        other.toDate == toDate &&
        other.kind == kind &&
        other.clientId == clientId &&
        other.descriptionQuery == descriptionQuery;
  }

  @override
  int get hashCode =>
      Object.hash(fromDate, toDate, kind, clientId, descriptionQuery);

  @override
  String toString() {
    return 'TransactionFilters('
        'hasFrom: ${fromDate != null}, '
        'hasTo: ${toDate != null}, '
        'kind: $kind, '
        'hasClientId: ${clientId != null && clientId!.isNotEmpty}, '
        'queryLength: ${descriptionQuery.length})';
  }
}
