import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
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

typedef DocumentDeleteMetadataExecutor =
    Future<DocumentMetadataDeleteResult> Function({
      required String companyId,
      required String documentId,
    });

typedef DocumentDeleteRowsExecutor =
    Future<List<Map<String, dynamic>>> Function({
      required String companyId,
      required String documentId,
    });

enum DocumentMetadataDeleteResult { deleted, alreadyAbsent }

class DocumentRemoteDataSource {
  DocumentRemoteDataSource(
    SupabaseClient client, {
    @visibleForTesting this._listExecutor,
    @visibleForTesting this._insertExecutor,
    @visibleForTesting this._updateExecutor,
    @visibleForTesting this._getExecutor,
    @visibleForTesting this._deleteMetadataExecutor,
    @visibleForTesting this._deleteRowsExecutor,
  }) : _client = client;

  @visibleForTesting
  DocumentRemoteDataSource.test({
    this._listExecutor,
    this._insertExecutor,
    this._updateExecutor,
    this._getExecutor,
    this._deleteMetadataExecutor,
    this._deleteRowsExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final DocumentsListExecutor? _listExecutor;
  final DocumentInsertExecutor? _insertExecutor;
  final DocumentUpdateExecutor? _updateExecutor;
  final DocumentGetExecutor? _getExecutor;
  final DocumentDeleteMetadataExecutor? _deleteMetadataExecutor;
  final DocumentDeleteRowsExecutor? _deleteRowsExecutor;

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

  /// Aggiorna atomicamente entrambi i collegamenti (UUID o null).
  Future<CompanyDocumentModel> updateLinks({
    required String companyId,
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) async {
    final executor = _updateExecutor ?? _executeUpdate;
    final row = await executor(
      companyId: companyId,
      documentId: documentId,
      values: <String, dynamic>{
        'client_id': clientId,
        'transaction_id': transactionId,
      },
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

  Future<DocumentMetadataDeleteResult> deleteDocumentMetadata({
    required String companyId,
    required String documentId,
  }) async {
    final executor = _deleteMetadataExecutor ?? _executeDeleteMetadata;
    return executor(companyId: companyId, documentId: documentId);
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

  Future<DocumentMetadataDeleteResult> _executeDeleteMetadata({
    required String companyId,
    required String documentId,
  }) async {
    final rowsExecutor = _deleteRowsExecutor ?? _executeDeleteRows;
    final rows = await rowsExecutor(
      companyId: companyId,
      documentId: documentId,
    );
    if (rows.isNotEmpty) {
      return DocumentMetadataDeleteResult.deleted;
    }

    // Zero righe: può essere già assente oppure no-op RLS. Verifica con get.
    final getExecutor = _getExecutor ?? _executeGet;
    try {
      await getExecutor(companyId: companyId, documentId: documentId);
      throw const DocumentMetadataDeleteNoOpException();
    } on PostgrestException catch (error) {
      if (_isPostgrestNotFound(error)) {
        return DocumentMetadataDeleteResult.alreadyAbsent;
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _executeDeleteRows({
    required String companyId,
    required String documentId,
  }) async {
    final response = await _client!
        .from('documents')
        .delete()
        .eq('company_id', companyId)
        .eq('id', documentId)
        .select('id');

    return (response as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  bool _isPostgrestNotFound(PostgrestException error) {
    final code = error.code ?? '';
    final combined =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce');
  }
}

enum DocumentStorageDeleteResult { deleted, alreadyAbsent }

typedef DocumentStorageUploadExecutor =
    Future<void> Function({
      required String path,
      required Uint8List bytes,
      required String mimeType,
    });

typedef DocumentStorageDeleteExecutor =
    Future<DocumentStorageDeleteResult> Function(String path);

typedef DocumentStorageExistsExecutor = Future<bool> Function(String path);

typedef DocumentStorageRemoveExecutor =
    Future<List<String>> Function(String path);

typedef DocumentStorageSignedUrlExecutor =
    Future<String> Function({required String path, required int expiresIn});

class DocumentStorageDataSource {
  DocumentStorageDataSource(
    SupabaseClient client, {
    @visibleForTesting this._uploadExecutor,
    @visibleForTesting this._deleteExecutor,
    @visibleForTesting this._removeExecutor,
    @visibleForTesting this._existsExecutor,
    @visibleForTesting this._signedUrlExecutor,
  }) : _client = client;

  @visibleForTesting
  DocumentStorageDataSource.test({
    this._uploadExecutor,
    this._deleteExecutor,
    this._removeExecutor,
    this._existsExecutor,
    this._signedUrlExecutor,
  }) : _client = null;

  final SupabaseClient? _client;
  final DocumentStorageUploadExecutor? _uploadExecutor;
  final DocumentStorageDeleteExecutor? _deleteExecutor;
  final DocumentStorageRemoveExecutor? _removeExecutor;
  final DocumentStorageExistsExecutor? _existsExecutor;
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

  /// Elimina l'oggetto distinguendo deleted / alreadyAbsent / no-op.
  Future<DocumentStorageDeleteResult> deleteObject(String path) async {
    final executor = _deleteExecutor ?? _executeDelete;
    return executor(path);
  }

  Future<bool> objectExists(String path) async {
    final executor = _existsExecutor ?? _executeObjectExists;
    return executor(path);
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

  Future<DocumentStorageDeleteResult> _executeDelete(String path) async {
    late final List<String> removedNames;
    try {
      final remove = _removeExecutor ?? _executeRemove;
      removedNames = await remove(path);
    } on StorageException catch (error) {
      final combined = '${error.message} ${error.statusCode ?? ''}'
          .toLowerCase();
      if (combined.contains('not found') || combined.contains('404')) {
        return DocumentStorageDeleteResult.alreadyAbsent;
      }
      rethrow;
    }

    if (_removedContainsPath(removedNames, path)) {
      return DocumentStorageDeleteResult.deleted;
    }

    final exists = await objectExists(path);
    if (!exists) {
      return DocumentStorageDeleteResult.alreadyAbsent;
    }
    throw const DocumentStorageDeleteNoOpException();
  }

  Future<List<String>> _executeRemove(String path) async {
    final removed = await _client!.storage.from(bucketId).remove([path]);
    return removed.map((file) => file.name).toList(growable: false);
  }

  /// Probe esistenza via list sul prefisso cartella + match esatto del nome.
  Future<bool> _executeObjectExists(String path) async {
    final segments = path.split('/');
    if (segments.length < 2) {
      throw StorageException('Invalid storage path');
    }
    final fileName = segments.last;
    final folder = segments.sublist(0, segments.length - 1).join('/');

    try {
      final listed = await _client!.storage
          .from(bucketId)
          .list(
            path: folder,
            searchOptions: SearchOptions(limit: 100, search: fileName),
          );
      return listed.any((file) => _namesMatch(file.name, path, fileName));
    } on StorageException catch (error) {
      final combined = '${error.message} ${error.statusCode ?? ''}'
          .toLowerCase();
      if (combined.contains('not found') || combined.contains('404')) {
        return false;
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

  static bool _removedContainsPath(List<String> removedNames, String path) {
    final fileName = path.split('/').last;
    return removedNames.any((name) => _namesMatch(name, path, fileName));
  }

  static bool _namesMatch(String name, String fullPath, String fileName) {
    return name == fullPath || name == fileName || name.endsWith('/$fileName');
  }
}
