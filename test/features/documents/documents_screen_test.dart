import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/documents/domain/entities/company_document.dart';
import 'package:project_atlas/features/documents/domain/entities/document_link_summaries.dart';
import 'package:project_atlas/features/documents/domain/repositories/document_repository.dart';
import 'package:project_atlas/features/documents/domain/services/document_url_launcher.dart';
import 'package:project_atlas/features/documents/presentation/providers/document_providers.dart';
import 'package:project_atlas/features/documents/presentation/screens/documents_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

ActiveCompanyContext _context({
  CompanyRole role = CompanyRole.owner,
  String companyId = 'c1',
}) {
  return ActiveCompanyContext(
    companyId: companyId,
    companyName: 'Acme',
    companySlug: 'acme',
    role: role,
    membershipId: 'm-$companyId',
  );
}

CompanyDocument _doc({
  String id = 'd1',
  String companyId = 'c1',
  bool archived = false,
  String title = 'Contratto',
  String? clientId,
  String? transactionId,
  String? clientName,
  String? transactionDescription,
}) {
  return CompanyDocument(
    id: id,
    companyId: companyId,
    uploadedBy: 'u1',
    title: title,
    originalFileName: 'contratto.pdf',
    storagePath: '$companyId/$id/o1.pdf',
    mimeType: 'application/pdf',
    sizeBytes: 2048,
    isArchived: archived,
    createdAt: DateTime.utc(2026, 7, 1, 10),
    updatedAt: DateTime.utc(2026, 7, 1, 10),
    clientId: clientId,
    transactionId: transactionId,
    clientSummary: clientName == null
        ? null
        : DocumentClientSummary(id: clientId ?? 'cl1', name: clientName),
    transactionSummary: transactionDescription == null
        ? null
        : DocumentTransactionSummary(
            id: transactionId ?? 't1',
            description: transactionDescription,
            amountCents: 1250,
            occurredOn: DateTime(2026, 7, 2),
            kind: DocumentTransactionKind.expense,
          ),
  );
}

class _FakeDocumentRepository implements DocumentRepository {
  _FakeDocumentRepository({this.listResult, this.signedUrlResult});

  Result<List<CompanyDocument>>? listResult;
  Result<String>? signedUrlResult;
  Result<void>? deleteResult;

  String? lastListCompanyId;
  String? lastRenamedTitle;
  bool? lastArchived;
  String? lastClientId;
  String? lastTransactionId;
  final List<String> deletedDocumentIds = [];

  @override
  Future<Result<List<CompanyDocument>>> getDocuments({
    required String companyId,
  }) async {
    lastListCompanyId = companyId;
    return listResult ?? const Success([]);
  }

  @override
  Future<Result<CompanyDocument>> uploadDocument({
    required String companyId,
    required String title,
    required String originalFileName,
    required String mimeType,
    required String canonicalExtension,
    required List<int> bytes,
  }) async {
    return Success(_doc(companyId: companyId, title: title));
  }

  @override
  Future<Result<String>> createSignedUrl({
    required String companyId,
    required String documentId,
  }) async {
    return signedUrlResult ?? const Success('https://example.test/signed');
  }

  @override
  Future<Result<CompanyDocument>> updateTitle({
    required String companyId,
    required String documentId,
    required String title,
  }) async {
    lastRenamedTitle = title;
    return Success(_doc(id: documentId, companyId: companyId, title: title));
  }

  @override
  Future<Result<CompanyDocument>> setArchived({
    required String companyId,
    required String documentId,
    required bool isArchived,
  }) async {
    lastArchived = isArchived;
    return Success(
      _doc(id: documentId, companyId: companyId, archived: isArchived),
    );
  }

  @override
  Future<Result<CompanyDocument>> updateDocumentLinks({
    required String companyId,
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) async {
    lastClientId = clientId;
    lastTransactionId = transactionId;
    return Success(
      _doc(
        id: documentId,
        companyId: companyId,
        clientId: clientId,
        transactionId: transactionId,
      ),
    );
  }

  @override
  Future<Result<void>> deleteDocumentPermanently({
    required String companyId,
    required String documentId,
  }) async {
    deletedDocumentIds.add(documentId);
    if (deleteResult != null) {
      return deleteResult!;
    }
    return const Success(null);
  }
}

class _FakeUrlLauncher implements DocumentUrlLauncher {
  String? lastUrl;
  bool openResult = true;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(String url) async {
    lastUrl = url;
    return openResult;
  }
}

Future<void> _pumpDocumentsScreen(
  WidgetTester tester, {
  required ActiveCompanyContext context,
  required DocumentRepository repository,
  DocumentUrlLauncher? launcher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeCompanyProvider.overrideWithValue(context),
        documentRepositoryProvider.overrideWithValue(repository),
        if (launcher != null)
          documentUrlLauncherProvider.overrideWithValue(launcher),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('it'),
        home: DocumentsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista empty e FAB per owner', (tester) async {
    final repo = _FakeDocumentRepository(listResult: const Success([]));
    await _pumpDocumentsScreen(tester, context: _context(), repository: repo);

    expect(
      find.text(
        'Nessun documento ancora. Carica il primo documento per iniziare.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('documents-upload-fab')), findsOneWidget);
  });

  testWidgets('employee read-only senza FAB', (tester) async {
    final repo = _FakeDocumentRepository(listResult: Success([_doc()]));
    await _pumpDocumentsScreen(
      tester,
      context: _context(role: CompanyRole.employee),
      repository: repo,
    );

    expect(find.text('Contratto'), findsOneWidget);
    expect(find.byKey(const Key('documents-upload-fab')), findsNothing);

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Apri'), findsOneWidget);
    expect(find.text('Rinomina'), findsNothing);
    expect(find.text('Archivia'), findsNothing);
  });

  testWidgets('errore con retry', (tester) async {
    final repo = _FakeDocumentRepository(
      listResult: const Error(
        NetworkFailure('Caricamento documenti non riuscito. Riprova.'),
      ),
    );
    await _pumpDocumentsScreen(tester, context: _context(), repository: repo);

    expect(
      find.text('Caricamento documenti non riuscito. Riprova.'),
      findsOneWidget,
    );
    expect(find.text('Riprova'), findsOneWidget);

    repo.listResult = Success([_doc()]);
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Contratto'), findsOneWidget);
  });

  testWidgets('tenant switch usa companyId attivo', (tester) async {
    final repo = _FakeDocumentRepository(
      listResult: Success([_doc(companyId: 'c2', title: 'Doc B')]),
    );
    await _pumpDocumentsScreen(
      tester,
      context: _context(companyId: 'c2'),
      repository: repo,
    );

    expect(repo.lastListCompanyId, 'c2');
    expect(find.text('Doc B'), findsOneWidget);
  });

  testWidgets('apertura signed URL', (tester) async {
    final repo = _FakeDocumentRepository(
      listResult: Success([_doc()]),
      signedUrlResult: const Success('https://example.test/doc.pdf'),
    );
    final launcher = _FakeUrlLauncher();
    await _pumpDocumentsScreen(
      tester,
      context: _context(),
      repository: repo,
      launcher: launcher,
    );

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    expect(launcher.lastUrl, 'https://example.test/doc.pdf');
  });

  testWidgets('URL non apribile mostra messaggio', (tester) async {
    final repo = _FakeDocumentRepository(listResult: Success([_doc()]));
    final launcher = _FakeUrlLauncher()..openResult = false;
    await _pumpDocumentsScreen(
      tester,
      context: _context(),
      repository: repo,
      launcher: launcher,
    );

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile aprire il documento.'), findsOneWidget);
  });

  testWidgets('manager vede azioni rinomina e archivia', (tester) async {
    final repo = _FakeDocumentRepository(listResult: Success([_doc()]));
    await _pumpDocumentsScreen(
      tester,
      context: _context(role: CompanyRole.manager),
      repository: repo,
    );

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Rinomina'), findsOneWidget);
    expect(find.text('Archivia'), findsOneWidget);
    expect(find.text('Gestisci collegamenti'), findsOneWidget);
    expect(find.text('Elimina definitivamente'), findsOneWidget);
    expect(find.text('Apri'), findsOneWidget);
  });

  testWidgets('employee senza link/delete nel menu', (tester) async {
    final repo = _FakeDocumentRepository(
      listResult: Success([
        _doc(
          clientId: 'cl1',
          clientName: 'Rossi',
          transactionId: 't1',
          transactionDescription: 'Affitto',
        ),
      ]),
    );
    await _pumpDocumentsScreen(
      tester,
      context: _context(role: CompanyRole.employee),
      repository: repo,
    );

    expect(find.textContaining('Cliente: Rossi'), findsOneWidget);
    expect(find.textContaining('Movimento: Affitto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Gestisci collegamenti'), findsNothing);
    expect(find.text('Elimina definitivamente'), findsNothing);
  });

  testWidgets('conferma eliminazione e successo', (tester) async {
    final repo = _FakeDocumentRepository(listResult: Success([_doc()]));
    await _pumpDocumentsScreen(tester, context: _context(), repository: repo);

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Questa operazione è irreversibile. Il documento e il file associato verranno eliminati.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('document-delete-confirm')));
    await tester.pumpAndSettle();

    expect(repo.deletedDocumentIds, ['d1']);
    expect(find.text('Documento eliminato.'), findsOneWidget);
  });

  testWidgets('eliminazione incompleta mostra errore', (tester) async {
    final repo = _FakeDocumentRepository(listResult: Success([_doc()]))
      ..deleteResult = const Error(IncompleteDocumentDeletionFailure());
    await _pumpDocumentsScreen(tester, context: _context(), repository: repo);

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Il file è stato rimosso, ma i dati del documento non sono stati eliminati',
      ),
      findsOneWidget,
    );
  });

  testWidgets('annulla eliminazione', (tester) async {
    final repo = _FakeDocumentRepository(listResult: Success([_doc()]));
    await _pumpDocumentsScreen(tester, context: _context(), repository: repo);

    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(repo.deletedDocumentIds, isEmpty);
  });

  testWidgets('documento archiviato distinguibile e riattivabile', (
    tester,
  ) async {
    final repo = _FakeDocumentRepository(
      listResult: Success([_doc(archived: true)]),
    );
    await _pumpDocumentsScreen(tester, context: _context(), repository: repo);

    expect(find.textContaining('Archiviato'), findsOneWidget);
    await tester.tap(find.byKey(const Key('document-menu-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Ripristina'), findsOneWidget);
    expect(find.text('Archivia'), findsNothing);
    expect(find.text('Elimina definitivamente'), findsOneWidget);
  });
}
