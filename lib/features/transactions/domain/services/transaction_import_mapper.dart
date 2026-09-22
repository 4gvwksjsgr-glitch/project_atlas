import '../entities/transaction_import_mapping.dart';
import '../value_objects/transaction_import_field.dart';

/// Auto-mapping conservativo: associa una colonna solo su sinonimo esatto
/// (italiano o inglese) e mai lo stesso campo due volte.
class TransactionImportMapper {
  const TransactionImportMapper();

  static const Map<TransactionImportField, Set<String>> _synonyms = {
    TransactionImportField.date: {
      'data',
      'data movimento',
      'data operazione',
      'data contabile',
      'data valuta',
      'date',
      'transaction date',
      'value date',
      'booking date',
    },
    TransactionImportField.description: {
      'descrizione',
      'causale',
      'descrizione operazione',
      'dettagli',
      'operazione',
      'description',
      'details',
      'memo',
      'narrative',
      'payee',
    },
    TransactionImportField.signedAmount: {
      'importo',
      'importo con segno',
      'ammontare',
      'valore',
      'amount',
      'signed amount',
      'value',
    },
    TransactionImportField.debit: {
      'dare',
      'uscite',
      'uscita',
      'addebito',
      'addebiti',
      'spesa',
      'spese',
      'debit',
      'debits',
      'withdrawal',
      'money out',
      'paid out',
    },
    TransactionImportField.credit: {
      'avere',
      'entrate',
      'entrata',
      'accredito',
      'accrediti',
      'incasso',
      'incassi',
      'credit',
      'credits',
      'deposit',
      'money in',
      'paid in',
    },
    TransactionImportField.reference: {
      'riferimento',
      'rif',
      'numero documento',
      'documento',
      'protocollo',
      'reference',
      'ref',
      'document number',
      'transaction id',
    },
    TransactionImportField.notes: {
      'note',
      'annotazioni',
      'commenti',
      'notes',
      'note aggiuntive',
      'comments',
      'remarks',
    },
  };

  TransactionImportMapping autoMap(List<String> headers) {
    final mapped = <int, TransactionImportField>{};
    final assignedFields = <TransactionImportField>{};

    for (var index = 0; index < headers.length; index++) {
      final normalizedHeader = normalizeHeader(headers[index]);
      final field = _synonyms.entries
          .where((entry) => entry.value.contains(normalizedHeader))
          .map((entry) => entry.key)
          .firstOrNull;

      if (field == null || assignedFields.contains(field)) {
        mapped[index] = TransactionImportField.ignore;
        continue;
      }

      mapped[index] = field;
      assignedFields.add(field);
    }

    // Colonna unica firmata e colonne dare/avere si escludono: senza una
    // coppia dare+avere completa le due colonne restano non mappate.
    final hasDebit = mapped.containsValue(TransactionImportField.debit);
    final hasCredit = mapped.containsValue(TransactionImportField.credit);
    final hasSigned = mapped.containsValue(TransactionImportField.signedAmount);

    if (hasSigned && (hasDebit || hasCredit)) {
      _unmap(mapped, TransactionImportField.debit);
      _unmap(mapped, TransactionImportField.credit);
    } else if (hasDebit != hasCredit) {
      _unmap(mapped, TransactionImportField.debit);
      _unmap(mapped, TransactionImportField.credit);
    }

    return TransactionImportMapping(mapped);
  }

  static void _unmap(
    Map<int, TransactionImportField> mapped,
    TransactionImportField field,
  ) {
    for (final entry in mapped.entries.toList()) {
      if (entry.value == field) {
        mapped[entry.key] = TransactionImportField.ignore;
      }
    }
  }

  static String normalizeHeader(String header) =>
      header.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
