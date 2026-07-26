import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_document_model.dart';

typedef DocumentsListExecutor =
    Future<List<Map<String, dynamic>>> Function({required String companyId});

typedef DocumentInsertExecutor =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

typedef DocumentUpdateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String documentId,
      required Map<String, dynamic> values,
    });

typedef DocumentGetExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String documentId,
    });

class DocumentRemoteDataSource {
  DocumentRemoteDataSource(
    SupabaseClient client, {
    @visibleForTesting this._listExecutor,
    @visibleForTesting this._insertExecutor,
    @visibleForTesting this._updateExecutor,
    @visibleForTesting this._getExecutor,
  }) : _client = client;

  @visibleForTesting
  DocumentRemoteDataSource.test({
    this._listExecutor,
    this._insertExecutor,
    this._updateExecutor,
    this._getExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final DocumentsListExecutor? _listExecutor;
  final DocumentInsertExecutor? _insertExecutor;
  final DocumentUpdateExecutor? _updateExecutor;
  final DocumentGetExecutor? _getExecutor;

  Future<List<CompanyDocumentModel>> getDocuments({
    required String companyId,
  }) async {
    final executor = _listExecutor ?? _executeList;
    final rows = await executor(companyId: companyId);
    return rows.map(CompanyDocumentModel.fromJson).toList();
  }

  Future<CompanyDocumentModel> insertDocument({
    required String id,
    required String companyId,
    required String title,
    required String originalFileName,
    required String storagePath,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      'company_id': companyId,
      'title': title,
      'original_file_name': originalFileName,
      'storage_path': storagePath,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    };
    final executor = _insertExecutor ?? _executeInsert;
    final row = await executor(payload);
    return CompanyDocumentModel.fromJson(row);
  }

  Future<CompanyDocumentModel> updateDocument({
    required String companyId,
    required String documentId,
    String? title,
    bool? isArchived,
  }) async {
    final values = <String, dynamic>{};
    if (title != null) {
      values['title'] = title;
    }
    if (isArchived != null) {
      values['is_archived'] = isArchived;
    }
    if (values.isEmpty) {
      throw ArgumentError('Nessun campo da aggiornare');
    }
    final executor = _updateExecutor ?? _executeUpdate;
    final row = await executor(
      companyId: companyId,
      documentId: documentId,
      values: values,
    );
    return CompanyDocumentModel.fromJson(row);
  }

  Future<CompanyDocumentModel> getDocument({
    required String companyId,
    required String documentId,
  }) async {
    final executor = _getExecutor ?? _executeGet;
    final row = await executor(companyId: companyId, documentId: documentId);
    return CompanyDocumentModel.fromJson(row);
  }

  Future<Map<String, dynamic>> _executeGet({
    required String companyId,
    required String documentId,
  }) async {
    final response = await _client!
        .from('documents')
        .select(CompanyDocumentModel.selectColumns)
        .eq('company_id', companyId)
        .eq('id', documentId)
        .single();
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> _executeList({
    required String companyId,
  }) async {
    final response = await _client!
        .from('documents')
        .select(CompanyDocumentModel.selectColumns)
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _executeInsert(
    Map<String, dynamic> payload,
  ) async {
    return await _client!
        .from('documents')
        .insert(payload)
        .select(CompanyDocumentModel.selectColumns)
        .single();
  }

  Future<Map<String, dynamic>> _executeUpdate({
    required String companyId,
    required String documentId,
    required Map<String, dynamic> values,
  }) async {
    return await _client!
        .from('documents')
        .update(values)
        .eq('id', documentId)
        .eq('company_id', companyId)
        .select(CompanyDocumentModel.selectColumns)
        .single();
  }
}

typedef DocumentStorageUploadExecutor =
    Future<void> Function({
      required String path,
      required Uint8List bytes,
      required String mimeType,
    });

typedef DocumentStorageDeleteExecutor = Future<void> Function(String path);

typedef DocumentStorageSignedUrlExecutor =
    Future<String> Function({required String path, required int expiresIn});

class DocumentStorageDataSource {
  DocumentStorageDataSource(
    SupabaseClient client, {
    @visibleForTesting this._uploadExecutor,
    @visibleForTesting this._deleteExecutor,
    @visibleForTesting this._signedUrlExecutor,
  }) : _client = client;

  @visibleForTesting
  DocumentStorageDataSource.test({
    this._uploadExecutor,
    this._deleteExecutor,
    this._signedUrlExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final DocumentStorageUploadExecutor? _uploadExecutor;
  final DocumentStorageDeleteExecutor? _deleteExecutor;
  final DocumentStorageSignedUrlExecutor? _signedUrlExecutor;

  static const bucketId = 'company-documents';

  Future<void> uploadObject({
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final executor = _uploadExecutor ?? _executeUpload;
    await executor(path: path, bytes: bytes, mimeType: mimeType);
  }

  /// Cleanup idempotente: assenza dell'oggetto non è errore.
  Future<void> deleteObject(String path) async {
    final executor = _deleteExecutor ?? _executeDelete;
    await executor(path);
  }

  Future<String> createSignedUrl({
    required String path,
    required int expiresIn,
  }) async {
    final executor = _signedUrlExecutor ?? _executeSignedUrl;
    return executor(path: path, expiresIn: expiresIn);
  }

  Future<void> _executeUpload({
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _client!.storage
        .from(bucketId)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  Future<void> _executeDelete(String path) async {
    try {
      await _client!.storage.from(bucketId).remove([path]);
    } on StorageException catch (error) {
      final combined = '${error.message} ${error.statusCode ?? ''}'
          .toLowerCase();
      if (combined.contains('not found') || combined.contains('404')) {
        return;
      }
      rethrow;
    }
  }

  Future<String> _executeSignedUrl({
    required String path,
    required int expiresIn,
  }) async {
    return _client!.storage.from(bucketId).createSignedUrl(path, expiresIn);
  }
}
