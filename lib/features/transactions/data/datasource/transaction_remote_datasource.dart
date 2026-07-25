import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/calendar_date.dart';
import '../../domain/value_objects/money_amount.dart';
import '../../domain/value_objects/transaction_filters.dart';
import '../models/cash_transaction_model.dart';

typedef TransactionsListExecutor =
    Future<List<Map<String, dynamic>>> Function({
      required String companyId,
      required TransactionFilters filters,
    });

typedef TransactionCreateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      String? clientId,
      String? categoryId,
      required TransactionKind kind,
      required MoneyAmount amount,
      required DateTime occurredOn,
      required String description,
      String? notes,
    });

typedef TransactionUpdateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String transactionId,
      String? clientId,
      String? categoryId,
      required TransactionKind kind,
      required MoneyAmount amount,
      required DateTime occurredOn,
      required String description,
      String? notes,
    });

class TransactionRemoteDataSource {
  TransactionRemoteDataSource(
    SupabaseClient client, {
    @visibleForTesting this._listExecutor,
    @visibleForTesting this._createExecutor,
    @visibleForTesting this._updateExecutor,
  }) : _client = client;

  @visibleForTesting
  TransactionRemoteDataSource.test({
    this._listExecutor,
    this._createExecutor,
    this._updateExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final TransactionsListExecutor? _listExecutor;
  final TransactionCreateExecutor? _createExecutor;
  final TransactionUpdateExecutor? _updateExecutor;

  Future<List<CashTransactionModel>> getTransactions({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _listExecutor ?? _executeList;
    final rows = await executor(companyId: companyId, filters: filters);
    return rows.map(CashTransactionModel.fromJson).toList();
  }

  Future<CashTransactionModel> createTransaction({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _createExecutor ?? _executeCreate;
    final response = await executor(
      companyId: companyId,
      clientId: clientId,
      categoryId: categoryId,
      kind: kind,
      amount: amount,
      occurredOn: occurredOn,
      description: description,
      notes: notes,
    );
    return CashTransactionModel.fromJson(response);
  }

  Future<CashTransactionModel> updateTransaction({
    required String companyId,
    required String transactionId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }
    if (transactionId.isEmpty) {
      throw ArgumentError.value(transactionId, 'transactionId', 'obbligatorio');
    }

    final executor = _updateExecutor ?? _executeUpdate;
    final response = await executor(
      companyId: companyId,
      transactionId: transactionId,
      clientId: clientId,
      categoryId: categoryId,
      kind: kind,
      amount: amount,
      occurredOn: occurredOn,
      description: description,
      notes: notes,
    );
    return CashTransactionModel.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> _executeList({
    required String companyId,
    required TransactionFilters filters,
  }) async {
    var query = _client!
        .from('transactions')
        .select(CashTransactionModel.selectColumns)
        .eq('company_id', companyId);

    if (filters.fromDate != null) {
      query = query.gte(
        'occurred_on',
        CalendarDate.toIsoDate(filters.fromDate!),
      );
    }
    if (filters.toDate != null) {
      query = query.lte('occurred_on', CalendarDate.toIsoDate(filters.toDate!));
    }
    if (filters.kind != null) {
      query = query.eq('kind', filters.kind!.dbValue);
    }
    final clientId = filters.clientId?.trim();
    if (clientId != null && clientId.isNotEmpty) {
      query = query.eq('client_id', clientId);
    }
    final descriptionQuery = filters.descriptionQuery.trim();
    if (descriptionQuery.isNotEmpty) {
      query = query.ilike(
        'description',
        '%${escapeIlikePattern(descriptionQuery)}%',
      );
    }

    final response = await query
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Escape per pattern ILIKE: evita che `%` / `_` dell'utente diventino wildcards.
  @visibleForTesting
  static String escapeIlikePattern(String raw) {
    return raw
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  Future<Map<String, dynamic>> _executeCreate({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'client_id': clientId,
      'category_id': categoryId,
      'kind': kind.dbValue,
      'amount': amount.toCanonicalDecimal(),
      'occurred_on': CalendarDate.toIsoDate(occurredOn),
      'description': description,
      'notes': notes,
    };

    return await _client!
        .from('transactions')
        .insert(payload)
        .select(CashTransactionModel.selectColumns)
        .single();
  }

  Future<Map<String, dynamic>> _executeUpdate({
    required String companyId,
    required String transactionId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    // Mai company_id nel payload di update.
    // category_id deve essere sempre presente (anche null) per consentire la rimozione.
    return await _client!
        .from('transactions')
        .update({
          'client_id': clientId,
          'category_id': categoryId,
          'kind': kind.dbValue,
          'amount': amount.toCanonicalDecimal(),
          'occurred_on': CalendarDate.toIsoDate(occurredOn),
          'description': description,
          'notes': notes,
        })
        .eq('id', transactionId)
        .eq('company_id', companyId)
        .select(CashTransactionModel.selectColumns)
        .single();
  }
}
