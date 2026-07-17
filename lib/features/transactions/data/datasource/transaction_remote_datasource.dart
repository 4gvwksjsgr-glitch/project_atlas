import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/calendar_date.dart';
import '../../domain/value_objects/money_amount.dart';
import '../models/cash_transaction_model.dart';

typedef TransactionsListExecutor =
    Future<List<Map<String, dynamic>>> Function({required String companyId});

typedef TransactionCreateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      String? clientId,
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
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _listExecutor ?? _executeList;
    final rows = await executor(companyId: companyId);
    return rows.map(CashTransactionModel.fromJson).toList();
  }

  Future<CashTransactionModel> createTransaction({
    required String companyId,
    String? clientId,
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
  }) async {
    final response = await _client!
        .from('transactions')
        .select(CashTransactionModel.selectColumns)
        .eq('company_id', companyId)
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _executeCreate({
    required String companyId,
    String? clientId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'client_id': clientId,
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
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    // Mai company_id nel payload di update.
    return await _client!
        .from('transactions')
        .update({
          'client_id': clientId,
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
