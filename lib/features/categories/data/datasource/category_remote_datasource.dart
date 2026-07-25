import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../transactions/domain/entities/cash_transaction.dart';
import '../models/transaction_category_model.dart';

typedef CategoriesListExecutor =
    Future<List<Map<String, dynamic>>> Function({required String companyId});

typedef CategoryCreateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String name,
      required TransactionKind kind,
    });

typedef CategoryRenameExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String categoryId,
      required String name,
    });

typedef CategorySetActiveExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String categoryId,
      required bool isActive,
    });

class CategoryRemoteDataSource {
  CategoryRemoteDataSource(
    SupabaseClient client, {
    @visibleForTesting this._listExecutor,
    @visibleForTesting this._createExecutor,
    @visibleForTesting this._renameExecutor,
    @visibleForTesting this._setActiveExecutor,
  }) : _client = client;

  @visibleForTesting
  CategoryRemoteDataSource.test({
    this._listExecutor,
    this._createExecutor,
    this._renameExecutor,
    this._setActiveExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final CategoriesListExecutor? _listExecutor;
  final CategoryCreateExecutor? _createExecutor;
  final CategoryRenameExecutor? _renameExecutor;
  final CategorySetActiveExecutor? _setActiveExecutor;

  Future<List<TransactionCategoryModel>> getCategories({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _listExecutor ?? _executeList;
    final rows = await executor(companyId: companyId);
    return rows.map(TransactionCategoryModel.fromJson).toList();
  }

  Future<TransactionCategoryModel> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _createExecutor ?? _executeCreate;
    final response = await executor(
      companyId: companyId,
      name: name,
      kind: kind,
    );
    return TransactionCategoryModel.fromJson(response);
  }

  Future<TransactionCategoryModel> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }
    if (categoryId.isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'obbligatorio');
    }

    final executor = _renameExecutor ?? _executeRename;
    final response = await executor(
      companyId: companyId,
      categoryId: categoryId,
      name: name,
    );
    return TransactionCategoryModel.fromJson(response);
  }

  Future<TransactionCategoryModel> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }
    if (categoryId.isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'obbligatorio');
    }

    final executor = _setActiveExecutor ?? _executeSetActive;
    final response = await executor(
      companyId: companyId,
      categoryId: categoryId,
      isActive: isActive,
    );
    return TransactionCategoryModel.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> _executeList({
    required String companyId,
  }) async {
    final response = await _client!
        .from('transaction_categories')
        .select(TransactionCategoryModel.selectColumns)
        .eq('company_id', companyId)
        .order('kind', ascending: true)
        .order('is_active', ascending: false)
        .order('name', ascending: true);

    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _executeCreate({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async {
    return await _client!
        .from('transaction_categories')
        .insert(
          buildCreatePayload(companyId: companyId, name: name, kind: kind),
        )
        .select(TransactionCategoryModel.selectColumns)
        .single();
  }

  /// Payload INSERT: solo colonne consentite dai privilegi least-privilege.
  @visibleForTesting
  static Map<String, dynamic> buildCreatePayload({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) {
    return {
      'company_id': companyId,
      'name': name,
      'kind': kind.dbValue,
      'is_active': true,
    };
  }

  Future<Map<String, dynamic>> _executeRename({
    required String companyId,
    required String categoryId,
    required String name,
  }) async {
    // Solo `name`: company_id e kind non sono aggiornabili (privilegi colonna + trigger).
    return await _client!
        .from('transaction_categories')
        .update({'name': name})
        .eq('id', categoryId)
        .eq('company_id', companyId)
        .select(TransactionCategoryModel.selectColumns)
        .single();
  }

  Future<Map<String, dynamic>> _executeSetActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async {
    return await _client!
        .from('transaction_categories')
        .update({'is_active': isActive})
        .eq('id', categoryId)
        .eq('company_id', companyId)
        .select(TransactionCategoryModel.selectColumns)
        .single();
  }
}
