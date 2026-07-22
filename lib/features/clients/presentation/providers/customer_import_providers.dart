import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/parsers/composite_customer_import_file_parser.dart';
import '../../data/repositories/customer_import_repository_impl.dart';
import '../../domain/repositories/customer_import_parser.dart';
import '../../domain/repositories/customer_import_repository.dart';
import '../../domain/usecases/import_customers.dart';
import 'customer_providers.dart';

final customerImportFileParserProvider = Provider<CustomerImportFileParser>((
  ref,
) {
  return const CompositeCustomerImportFileParser();
});

final customerImportRepositoryProvider = Provider<CustomerImportRepository>((
  ref,
) {
  return CustomerImportRepositoryImpl(
    ref.watch(customerRemoteDataSourceProvider),
  );
});

final importCustomersUseCaseProvider = Provider<ImportCustomers>((ref) {
  return ImportCustomers(ref.watch(customerImportRepositoryProvider));
});
