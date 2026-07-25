import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/categories/domain/entities/transaction_category.dart';
import 'package:project_atlas/features/categories/presentation/providers/category_providers.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/presentation/widgets/transaction_category_picker.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

TransactionCategory _category({
  required String id,
  required String name,
  required TransactionKind kind,
  bool isActive = true,
  String companyId = 'c1',
}) {
  return TransactionCategory(
    id: id,
    companyId: companyId,
    name: name,
    kind: kind,
    isActive: isActive,
    createdAt: DateTime.utc(2026, 7, 25),
    updatedAt: DateTime.utc(2026, 7, 25),
  );
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required AsyncValue<List<TransactionCategory>> categories,
  required TransactionKind kind,
  String? selectedCategoryId,
  TransactionCategory? keptArchivedCategory,
  bool canEdit = true,
  ValueChanged<String?>? onSelected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        categoriesProvider.overrideWith((ref, companyId) {
          return categories.when(
            data: (value) async => value,
            error: (error, stackTrace) async =>
                Future<List<TransactionCategory>>.error(error, stackTrace),
            loading: () => Completer<List<TransactionCategory>>().future,
          );
        }),
      ],
      child: MaterialApp(
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TransactionCategoryPicker(
            companyId: 'c1',
            kind: kind,
            selectedCategoryId: selectedCategoryId,
            keptArchivedCategory: keptArchivedCategory,
            canEdit: canEdit,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransactionCategoryPicker', () {
    testWidgets('mostra loading', (tester) async {
      await _pumpPicker(
        tester,
        categories: const AsyncLoading(),
        kind: TransactionKind.expense,
      );

      expect(find.text('Caricamento categorie...'), findsOneWidget);
    });

    testWidgets('mostra errore con retry', (tester) async {
      await _pumpPicker(
        tester,
        categories: AsyncError(Exception('boom'), StackTrace.current),
        kind: TransactionKind.expense,
      );
      await tester.pump();

      expect(
        find.text('Caricamento categorie non riuscito. Riprova.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('transaction-categories-retry')),
        findsOneWidget,
      );
    });

    testWidgets('mostra empty state', (tester) async {
      await _pumpPicker(
        tester,
        categories: const AsyncData([]),
        kind: TransactionKind.expense,
      );
      await tester.pumpAndSettle();

      expect(find.text('Nessuna categoria'), findsOneWidget);
      expect(
        find.text('Nessuna categoria disponibile per questo tipo.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('transaction-categories-manage-link')),
        findsOneWidget,
      );
    });

    testWidgets('filtra categorie income', (tester) async {
      await _pumpPicker(
        tester,
        categories: AsyncData([
          _category(id: 'e1', name: 'Affitto', kind: TransactionKind.expense),
          _category(id: 'i1', name: 'Vendite', kind: TransactionKind.income),
          _category(id: 'i2', name: 'Consulenze', kind: TransactionKind.income),
        ]),
        kind: TransactionKind.income,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transaction-category-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Vendite'), findsWidgets);
      expect(find.text('Consulenze'), findsOneWidget);
      expect(find.text('Affitto'), findsNothing);
    });

    testWidgets('filtra categorie expense', (tester) async {
      await _pumpPicker(
        tester,
        categories: AsyncData([
          _category(id: 'e1', name: 'Affitto', kind: TransactionKind.expense),
          _category(id: 'i1', name: 'Vendite', kind: TransactionKind.income),
        ]),
        kind: TransactionKind.expense,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transaction-category-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Affitto'), findsWidgets);
      expect(find.text('Vendite'), findsNothing);
    });

    testWidgets('nasconde categoria archiviata non corrente', (tester) async {
      await _pumpPicker(
        tester,
        categories: AsyncData([
          _category(id: 'a1', name: 'Attiva', kind: TransactionKind.expense),
          _category(
            id: 'arch',
            name: 'Vecchia',
            kind: TransactionKind.expense,
            isActive: false,
          ),
        ]),
        kind: TransactionKind.expense,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transaction-category-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Attiva'), findsWidgets);
      expect(find.textContaining('Vecchia'), findsNothing);
    });

    testWidgets(
      'mostra categoria archiviata corrente con suffisso Archiviata',
      (tester) async {
        final archived = _category(
          id: 'arch',
          name: 'Legacy',
          kind: TransactionKind.expense,
          isActive: false,
        );
        await _pumpPicker(
          tester,
          categories: AsyncData([
            _category(id: 'a1', name: 'Attiva', kind: TransactionKind.expense),
            archived,
          ]),
          kind: TransactionKind.expense,
          selectedCategoryId: archived.id,
          keptArchivedCategory: archived,
        );
        await tester.pumpAndSettle();

        expect(find.text('Legacy (Archiviata)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('transaction-category-menu')));
        await tester.pumpAndSettle();

        expect(find.text('Legacy (Archiviata)'), findsWidgets);
        expect(find.text('Attiva'), findsOneWidget);
      },
    );

    testWidgets('selezione di una categoria attiva', (tester) async {
      String? selected;
      await _pumpPicker(
        tester,
        categories: AsyncData([
          _category(id: 'e1', name: 'Affitto', kind: TransactionKind.expense),
        ]),
        kind: TransactionKind.expense,
        onSelected: (value) => selected = value,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transaction-category-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Affitto').last);
      await tester.pumpAndSettle();

      expect(selected, 'e1');
    });

    testWidgets('selezione Nessuna categoria', (tester) async {
      String? selected = 'e1';
      await _pumpPicker(
        tester,
        categories: AsyncData([
          _category(id: 'e1', name: 'Affitto', kind: TransactionKind.expense),
        ]),
        kind: TransactionKind.expense,
        selectedCategoryId: 'e1',
        onSelected: (value) => selected = value,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transaction-category-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nessuna categoria').last);
      await tester.pumpAndSettle();

      expect(selected, isNull);
    });

    testWidgets('picker disabilitato per utente read-only', (tester) async {
      await _pumpPicker(
        tester,
        categories: AsyncData([
          _category(id: 'e1', name: 'Affitto', kind: TransactionKind.expense),
        ]),
        kind: TransactionKind.expense,
        canEdit: false,
      );
      await tester.pumpAndSettle();

      final menu = tester.widget<PopupMenuButton<String>>(
        find.byKey(const Key('transaction-category-menu')),
      );
      expect(menu.enabled, isFalse);
    });
  });
}
