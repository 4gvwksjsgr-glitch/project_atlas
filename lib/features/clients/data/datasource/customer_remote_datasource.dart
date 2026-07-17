import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_model.dart';

typedef CustomersListExecutor =
    Future<List<Map<String, dynamic>>> Function({required String companyId});

typedef CustomerCreateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String name,
      String? email,
      String? phone,
      String? notes,
    });

typedef CustomerUpdateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String customerId,
      required String name,
      String? email,
      String? phone,
      String? notes,
    });

class CustomerRemoteDataSource {
  CustomerRemoteDataSource(
    SupabaseClient client, {
    @visibleForTesting this._listExecutor,
    @visibleForTesting this._createExecutor,
    @visibleForTesting this._updateExecutor,
  }) : _client = client;

  @visibleForTesting
  CustomerRemoteDataSource.test({
    this._listExecutor,
    this._createExecutor,
    this._updateExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final CustomersListExecutor? _listExecutor;
  final CustomerCreateExecutor? _createExecutor;
  final CustomerUpdateExecutor? _updateExecutor;

  Future<List<CustomerModel>> getCustomers({required String companyId}) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _listExecutor ?? _executeList;
    final rows = await executor(companyId: companyId);
    return rows.map(CustomerModel.fromJson).toList();
  }

  Future<CustomerModel> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _createExecutor ?? _executeCreate;
    final response = await executor(
      companyId: companyId,
      name: name,
      email: email,
      phone: phone,
      notes: notes,
    );
    return CustomerModel.fromJson(response);
  }

  Future<CustomerModel> updateCustomer({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }
    if (customerId.isEmpty) {
      throw ArgumentError.value(customerId, 'customerId', 'obbligatorio');
    }

    final executor = _updateExecutor ?? _executeUpdate;
    final response = await executor(
      companyId: companyId,
      customerId: customerId,
      name: name,
      email: email,
      phone: phone,
      notes: notes,
    );
    return CustomerModel.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> _executeList({
    required String companyId,
  }) async {
    final response = await _client!
        .from('clients')
        .select(CustomerModel.selectColumns)
        .eq('company_id', companyId)
        .order('name');

    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _executeCreate({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'name': name,
      'email': email,
      'phone': phone,
      'notes': notes,
    };

    return await _client!
        .from('clients')
        .insert(payload)
        .select(CustomerModel.selectColumns)
        .single();
  }

  Future<Map<String, dynamic>> _executeUpdate({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    return await _client!
        .from('clients')
        .update({'name': name, 'email': email, 'phone': phone, 'notes': notes})
        .eq('id', customerId)
        .eq('company_id', companyId)
        .select(CustomerModel.selectColumns)
        .single();
  }
}
