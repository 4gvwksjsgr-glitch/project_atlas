import '../entities/customer_import_mapping.dart';
import '../value_objects/customer_import_field.dart';

class CustomerImportMapper {
  const CustomerImportMapper();

  static const Map<CustomerImportField, Set<String>> _synonyms = {
    CustomerImportField.name: {
      'cliente',
      'nome',
      'nominativo',
      'ragione sociale',
      'denominazione',
    },
    CustomerImportField.email: {'email', 'e-mail', 'mail', 'posta elettronica'},
    CustomerImportField.phone: {
      'telefono',
      'cellulare',
      'telefono cliente',
      'tel',
      'mobile',
    },
    CustomerImportField.notes: {'note', 'annotazioni', 'commenti'},
  };

  CustomerImportMapping autoMap(List<String> headers) {
    final mapped = <int, CustomerImportField>{};
    final assignedFields = <CustomerImportField>{};

    for (var index = 0; index < headers.length; index++) {
      final normalizedHeader = normalizeHeader(headers[index]);
      final field = _synonyms.entries
          .where((entry) => entry.value.contains(normalizedHeader))
          .map((entry) => entry.key)
          .firstOrNull;

      if (field == null || assignedFields.contains(field)) {
        mapped[index] = CustomerImportField.ignore;
        continue;
      }

      mapped[index] = field;
      assignedFields.add(field);
    }

    return CustomerImportMapping(mapped);
  }

  static String normalizeHeader(String header) =>
      header.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
