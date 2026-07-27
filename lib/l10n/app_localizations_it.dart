// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Project Atlas';

  @override
  String get loginTitle => 'Accedi';

  @override
  String get loginSubtitle => 'Inserisci le tue credenziali per continuare';

  @override
  String get signupTitle => 'Registrati';

  @override
  String get signupSubtitle => 'Crea un account per iniziare';

  @override
  String get forgotPasswordTitle => 'Recupera password';

  @override
  String get forgotPasswordSubtitle =>
      'Inserisci la tua email per ricevere il link di reset';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Accedi';

  @override
  String get signupButton => 'Registrati';

  @override
  String get forgotPasswordButton => 'Invia link di reset';

  @override
  String get goToSignup => 'Non hai un account? Registrati';

  @override
  String get goToLogin => 'Hai già un account? Accedi';

  @override
  String get goToForgotPassword => 'Password dimenticata?';

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get dashboardWelcome => 'Benvenuto in Project Atlas';

  @override
  String get dashboardNoActiveCompany =>
      'Nessuna azienda attiva. Seleziona un\'azienda per continuare.';

  @override
  String get dashboardMembersTitle => 'Membri';

  @override
  String get dashboardMembersLoading => 'Caricamento membri...';

  @override
  String get dashboardMembersError =>
      'Caricamento membri non riuscito. Riprova.';

  @override
  String get dashboardMembersRetry => 'Riprova';

  @override
  String dashboardMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membri',
      one: '1 membro',
      zero: 'Nessun membro',
    );
    return '$_temp0';
  }

  @override
  String get dashboardCashTitle => 'Riepilogo economico';

  @override
  String get dashboardCashLoading => 'Caricamento riepilogo economico...';

  @override
  String get dashboardCashError =>
      'Caricamento riepilogo economico non riuscito. Riprova.';

  @override
  String get dashboardCashRetry => 'Riprova';

  @override
  String get dashboardCashEmpty => 'Nessun movimento ancora';

  @override
  String get dashboardCashTotalSection => 'Totale';

  @override
  String get dashboardCashMonthSection => 'Mese corrente';

  @override
  String get dashboardCashIncome => 'Entrate';

  @override
  String get dashboardCashExpense => 'Uscite';

  @override
  String get dashboardCashBalance => 'Saldo';

  @override
  String get dashboardCashMovements => 'Movimenti';

  @override
  String get dashboardCashSeeTransactions => 'Vedi movimenti';

  @override
  String get logoutButton => 'Esci';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navClients => 'Clienti';

  @override
  String get navTransactions => 'Movimenti';

  @override
  String get navDocuments => 'Documenti';

  @override
  String get navSettings => 'Impostazioni';

  @override
  String get cancel => 'Annulla';

  @override
  String get save => 'Salva';

  @override
  String get documentsTitle => 'Documenti';

  @override
  String get documentsEmpty =>
      'Nessun documento ancora. Carica il primo documento per iniziare.';

  @override
  String get documentsLoadError =>
      'Caricamento documenti non riuscito. Riprova.';

  @override
  String get documentsRetry => 'Riprova';

  @override
  String get documentsUpload => 'Carica documento';

  @override
  String get documentsUploadConfirm => 'Carica';

  @override
  String get documentsUploadSuccess => 'Documento caricato.';

  @override
  String get documentsUploadError =>
      'Caricamento documento non riuscito. Riprova.';

  @override
  String get documentTitleLabel => 'Titolo';

  @override
  String get documentOpen => 'Apri';

  @override
  String get documentOpenFailed => 'Impossibile aprire il documento.';

  @override
  String get documentRename => 'Rinomina';

  @override
  String get documentRenameSuccess => 'Titolo aggiornato.';

  @override
  String get documentRenameError =>
      'Aggiornamento titolo non riuscito. Riprova.';

  @override
  String get documentArchive => 'Archivia';

  @override
  String get documentRestore => 'Ripristina';

  @override
  String get documentArchived => 'Archiviato';

  @override
  String get documentArchiveSuccess => 'Documento archiviato.';

  @override
  String get documentRestoreSuccess => 'Documento ripristinato.';

  @override
  String get documentArchiveError =>
      'Aggiornamento archivio non riuscito. Riprova.';

  @override
  String get documentReadOnlyMessage =>
      'Non hai i permessi per caricare o modificare i documenti. Puoi solo visualizzarli e aprirli.';

  @override
  String get documentManageLinks => 'Gestisci collegamenti';

  @override
  String get documentLinksClient => 'Cliente';

  @override
  String get documentLinksTransaction => 'Movimento';

  @override
  String get documentLinksNoClient => 'Nessun cliente';

  @override
  String get documentLinksNoTransaction => 'Nessun movimento';

  @override
  String get documentLinksSave => 'Salva collegamenti';

  @override
  String get documentLinksSuccess => 'Collegamenti aggiornati.';

  @override
  String get documentLinksError =>
      'Aggiornamento collegamenti non riuscito. Riprova.';

  @override
  String get documentLinksSearchClient => 'Cerca cliente';

  @override
  String get documentLinksSearchTransaction => 'Cerca movimento';

  @override
  String get documentLinksEmptyClients => 'Nessun cliente disponibile.';

  @override
  String get documentLinksEmptyTransactions => 'Nessun movimento disponibile.';

  @override
  String get documentDeletePermanently => 'Elimina definitivamente';

  @override
  String get documentDeleteConfirmTitle => 'Elimina definitivamente';

  @override
  String get documentDeleteIrreversible =>
      'Questa operazione è irreversibile. Il documento e il file associato verranno eliminati.';

  @override
  String get documentDeleteConfirmAction => 'Elimina definitivamente';

  @override
  String get documentDeleteSuccess => 'Documento eliminato.';

  @override
  String get documentDeleteError =>
      'Eliminazione documento non riuscita. Riprova.';

  @override
  String get documentDeleteIncomplete =>
      'Eliminazione incompleta. Il file è stato rimosso ma i dati restano. Riprova.';

  @override
  String documentLinkedClient(String name) {
    return 'Cliente: $name';
  }

  @override
  String documentLinkedTransaction(String summary) {
    return 'Movimento: $summary';
  }

  @override
  String get customersTitle => 'Clienti';

  @override
  String get customersSubtitle => 'Anagrafica clienti dell\'azienda attiva';

  @override
  String get customersNoActiveCompany =>
      'Nessuna azienda attiva. Seleziona un\'azienda per continuare.';

  @override
  String get customersEmpty =>
      'Nessun cliente ancora. Aggiungi il primo cliente per iniziare.';

  @override
  String get customersLoadError => 'Caricamento clienti non riuscito. Riprova.';

  @override
  String get customersRetry => 'Riprova';

  @override
  String get customersNewButton => 'Nuovo cliente';

  @override
  String get customersImportButton => 'Importa clienti';

  @override
  String get customersImportTitle => 'Importa clienti';

  @override
  String get customersImportForbidden =>
      'Non hai i permessi per importare clienti.';

  @override
  String get customersImportIntro =>
      'Importa un elenco clienti da file CSV o Excel nell\'azienda attiva.';

  @override
  String get customersImportFieldsNotice =>
      'Questa versione importa soltanto: Nome o ragione sociale, Email, Telefono, Note.';

  @override
  String get customersImportLimits =>
      'Limiti: file fino a 2 MB, massimo 500 righe dati, massimo 20 fogli Excel, un foglio alla volta.';

  @override
  String get customersImportPickFile => 'Seleziona file CSV o XLSX';

  @override
  String get customersImportPickSheet => 'Scegli il foglio da importare';

  @override
  String get customersImportMappingTitle => 'Associa le colonne';

  @override
  String get customersImportMappingHint =>
      'Il campo Nome o ragione sociale è obbligatorio. Ogni campo può essere associato a una sola colonna.';

  @override
  String get customersImportFieldName => 'Nome o ragione sociale';

  @override
  String get customersImportFieldEmail => 'Email';

  @override
  String get customersImportFieldPhone => 'Telefono';

  @override
  String get customersImportFieldNotes => 'Note';

  @override
  String get customersImportFieldIgnore => 'Ignora';

  @override
  String get customersImportContinue => 'Continua';

  @override
  String get customersImportSummaryTitle => 'Riepilogo analisi';

  @override
  String customersImportSummaryRead(int count) {
    return 'Righe lette: $count';
  }

  @override
  String customersImportSummaryValid(int count) {
    return 'Clienti validi: $count';
  }

  @override
  String customersImportSummaryDuplicates(int count) {
    return 'Duplicati esclusi: $count';
  }

  @override
  String customersImportSummaryErrors(int count) {
    return 'Righe con errori: $count';
  }

  @override
  String customersImportSummaryEmpty(int count) {
    return 'Righe vuote ignorate: $count';
  }

  @override
  String customersImportSummaryWarnings(int count) {
    return 'Avvisi: $count';
  }

  @override
  String get customersImportPreviewTitle => 'Anteprima (prime 20 righe)';

  @override
  String customersImportPreviewRowTitle(int row, String status) {
    return 'Riga $row · $status';
  }

  @override
  String get customersImportPreviewStatusError => 'errore';

  @override
  String get customersImportPreviewStatusDuplicate => 'duplicato';

  @override
  String get customersImportPreviewStatusOk => 'ok';

  @override
  String customersImportIssueWithRow(int row, String message) {
    return 'Riga $row — $message';
  }

  @override
  String get customersImportIssueLeadingZeroRisk =>
      'Questa cella numerica potrebbe aver perso uno zero iniziale.';

  @override
  String get customersImportIssueDuplicateEmailInFile =>
      'Email duplicata nel file: la riga verrà esclusa.';

  @override
  String get customersImportIssueDuplicateEmailInDatabase =>
      'Email già presente tra i clienti dell\'azienda: la riga verrà esclusa.';

  @override
  String get customersImportIssueMissingName =>
      'Nome o ragione sociale mancante.';

  @override
  String get customersImportIssueInvalidEmail => 'Indirizzo email non valido.';

  @override
  String get customersImportIssueNameTooLong =>
      'Nome o ragione sociale troppo lungo.';

  @override
  String get customersImportIssueEmailTooLong =>
      'Indirizzo email troppo lungo.';

  @override
  String get customersImportIssuePhoneTooLong =>
      'Numero di telefono troppo lungo.';

  @override
  String get customersImportIssueNotesTooLong => 'Note troppo lunghe.';

  @override
  String get customersImportIssueFormulaNotSupported =>
      'Le formule Excel non sono supportate in questo campo.';

  @override
  String get customersImportIssueInvalidCellType =>
      'Tipo di cella non supportato.';

  @override
  String get customersImportIssueDuplicateNameWarning =>
      'Esiste già una riga con lo stesso nome: controlla che non sia un duplicato.';

  @override
  String get customersImportIssueGeneric => 'Problema nella riga.';

  @override
  String get customersImportConfirm => 'Conferma importazione';

  @override
  String get customersImportResultTitle => 'Importazione completata';

  @override
  String customersImportResultInserted(int count) {
    return 'Clienti inseriti: $count';
  }

  @override
  String customersImportResultSkipped(int count) {
    return 'Duplicati esclusi dal server: $count';
  }

  @override
  String get customersImportBackToList => 'Torna ai clienti';

  @override
  String get customerNewTitle => 'Nuovo cliente';

  @override
  String get customerEditTitle => 'Modifica cliente';

  @override
  String get customerNotFound => 'Cliente non trovato.';

  @override
  String get customerReadOnlyMessage =>
      'Non hai i permessi per modificare i clienti. Contatta un proprietario, un amministratore o un manager.';

  @override
  String get customerNameLabel => 'Nome';

  @override
  String get customerNameRequired => 'Inserisci il nome del cliente';

  @override
  String get customerEmailLabel => 'Email';

  @override
  String get customerPhoneLabel => 'Telefono';

  @override
  String get customerNotesLabel => 'Note';

  @override
  String get customerSaveButton => 'Salva';

  @override
  String get customerCreateSuccess => 'Cliente creato correttamente.';

  @override
  String get customerUpdateSuccess => 'Cliente aggiornato correttamente.';

  @override
  String get transactionsTitle => 'Movimenti';

  @override
  String get transactionsSubtitle => 'Entrate e uscite dell\'azienda attiva';

  @override
  String get transactionsNoActiveCompany =>
      'Nessuna azienda attiva. Seleziona un\'azienda per continuare.';

  @override
  String get transactionsEmpty =>
      'Nessun movimento ancora. Aggiungi il primo movimento per iniziare.';

  @override
  String get transactionsFilterEmpty =>
      'Nessun movimento corrisponde ai filtri selezionati.';

  @override
  String transactionsResultsCount(int count) {
    return 'Risultati trovati: $count';
  }

  @override
  String get transactionsFiltersTitle => 'Filtri';

  @override
  String get transactionsFilterFromDate => 'Dal';

  @override
  String get transactionsFilterToDate => 'Al';

  @override
  String get transactionsFilterPickDate => 'Scegli data';

  @override
  String get transactionsFilterKindAll => 'Tutti';

  @override
  String get transactionsFilterClientAll => 'Tutti i clienti';

  @override
  String get transactionsFilterDescriptionHint => 'Cerca nella descrizione';

  @override
  String get transactionsFilterClear => 'Cancella filtri';

  @override
  String get transactionsLoadError =>
      'Caricamento movimenti non riuscito. Riprova.';

  @override
  String get transactionsRetry => 'Riprova';

  @override
  String get transactionsNewButton => 'Nuovo movimento';

  @override
  String get transactionNewTitle => 'Nuovo movimento';

  @override
  String get transactionEditTitle => 'Modifica movimento';

  @override
  String get transactionNotFound => 'Movimento non trovato.';

  @override
  String get transactionReadOnlyMessage =>
      'Non hai i permessi per modificare i movimenti. Contatta un proprietario, un amministratore o un manager.';

  @override
  String get transactionKindLabel => 'Tipo';

  @override
  String get transactionKindIncome => 'Entrata';

  @override
  String get transactionKindExpense => 'Uscita';

  @override
  String get transactionAmountLabel => 'Importo (€)';

  @override
  String get transactionAmountRequired => 'Inserisci l\'importo';

  @override
  String get transactionAmountInvalid =>
      'Inserisci un importo valido maggiore di zero';

  @override
  String get transactionDateLabel => 'Data movimento';

  @override
  String get transactionDescriptionLabel => 'Descrizione';

  @override
  String get transactionDescriptionRequired => 'Inserisci la descrizione';

  @override
  String get transactionNotesLabel => 'Note';

  @override
  String get transactionClientLabel => 'Cliente';

  @override
  String get transactionClientNone => 'Nessun cliente';

  @override
  String get transactionClientsLoading => 'Caricamento clienti...';

  @override
  String get transactionClientsLoadError =>
      'Clienti non disponibili. Puoi comunque salvare senza cliente.';

  @override
  String get transactionSaveButton => 'Salva';

  @override
  String get transactionCreateSuccess => 'Movimento creato correttamente.';

  @override
  String get transactionUpdateSuccess => 'Movimento aggiornato correttamente.';

  @override
  String get transactionCategoryLabel => 'Categoria';

  @override
  String get transactionCategoryNone => 'Nessuna categoria';

  @override
  String get transactionCategoryArchived => 'Archiviata';

  @override
  String get transactionCategoriesLoading => 'Caricamento categorie...';

  @override
  String get transactionCategoriesLoadError =>
      'Caricamento categorie non riuscito. Riprova.';

  @override
  String get transactionCategoriesEmpty =>
      'Nessuna categoria disponibile per questo tipo.';

  @override
  String get transactionCategoriesManageLink => 'Gestisci categorie';

  @override
  String get transactionCategoryInvalid =>
      'La categoria selezionata non è valida per questo movimento.';

  @override
  String get companySettingsTitle => 'Impostazioni azienda';

  @override
  String get companySettingsSubtitle =>
      'Visualizza e aggiorna i dati dell\'azienda attiva';

  @override
  String get companySettingsNoActiveCompany =>
      'Nessuna azienda attiva. Seleziona un\'azienda per continuare.';

  @override
  String get companySettingsReadOnlyMessage =>
      'Non hai i permessi per modificare questa azienda. Contatta un proprietario o un amministratore.';

  @override
  String get companySettingsSaveButton => 'Salva modifiche';

  @override
  String get companySettingsSaveSuccess => 'Azienda aggiornata correttamente.';

  @override
  String get categoriesTitle => 'Categorie';

  @override
  String get categoriesSubtitle =>
      'Categorie operative di entrate e uscite (non fiscali).';

  @override
  String get categoriesSettingsLinkSubtitle =>
      'Gestisci le categorie dei movimenti';

  @override
  String get categoriesNoActiveCompany =>
      'Nessuna azienda attiva. Seleziona un\'azienda per continuare.';

  @override
  String get categoriesReadOnlyMessage =>
      'Puoi visualizzare le categorie, ma non modificarle.';

  @override
  String get categoriesEmpty =>
      'Nessuna categoria ancora. Aggiungi la prima categoria operativa.';

  @override
  String get categoriesSectionEmpty => 'Nessuna categoria in questa sezione.';

  @override
  String get categoriesLoadError =>
      'Caricamento categorie non riuscito. Riprova.';

  @override
  String get categoriesRetry => 'Riprova';

  @override
  String get categoriesNewButton => 'Nuova categoria';

  @override
  String get categoriesCreateTitle => 'Nuova categoria';

  @override
  String get categoriesRenameTitle => 'Rinomina categoria';

  @override
  String get categoriesNameLabel => 'Nome';

  @override
  String get categoriesNameRequired =>
      'Il nome della categoria è obbligatorio.';

  @override
  String get categoriesNameTooLong =>
      'Il nome della categoria non può superare i 80 caratteri.';

  @override
  String get categoriesCancel => 'Annulla';

  @override
  String get categoriesSave => 'Salva';

  @override
  String get categoriesIncomeSection => 'Entrate';

  @override
  String get categoriesExpenseSection => 'Uscite';

  @override
  String get categoriesActiveGroup => 'Attive';

  @override
  String get categoriesArchivedGroup => 'Archiviate';

  @override
  String get categoriesArchivedBadge => 'Archiviata';

  @override
  String get categoriesRenameAction => 'Rinomina';

  @override
  String get categoriesArchiveAction => 'Archivia';

  @override
  String get categoriesReactivateAction => 'Riattiva';

  @override
  String get categoriesCreateSuccess => 'Categoria creata.';

  @override
  String get categoriesRenameSuccess => 'Categoria rinominata.';

  @override
  String get categoriesArchiveSuccess => 'Categoria archiviata.';

  @override
  String get categoriesReactivateSuccess => 'Categoria riattivata.';

  @override
  String get emailRequired => 'Inserisci l\'email';

  @override
  String get emailInvalid => 'Inserisci un\'email valida';

  @override
  String get passwordRequired => 'Inserisci la password';

  @override
  String get passwordTooShort => 'La password deve avere almeno 8 caratteri';

  @override
  String get confirmPasswordLabel => 'Conferma password';

  @override
  String get confirmPasswordRequired => 'Conferma la password';

  @override
  String get confirmPasswordMismatch => 'Le password non coincidono';

  @override
  String get checkEmailTitle => 'Controlla la tua email';

  @override
  String get checkEmailSubtitle =>
      'Ti abbiamo inviato un link per confermare l\'account';

  @override
  String get checkEmailBackToLogin => 'Torna al login';

  @override
  String get onboardingCompanyTitle => 'Configura la tua azienda';

  @override
  String get onboardingCompanySubtitle =>
      'Crea la prima azienda per iniziare a usare Project Atlas';

  @override
  String get companyNameLabel => 'Nome azienda';

  @override
  String get companyNameRequired => 'Inserisci il nome dell\'azienda';

  @override
  String get companySlugLabel => 'Slug';

  @override
  String get companySlugHelper =>
      'Identificativo univoco dell\'azienda nell\'URL';

  @override
  String get companySlugRequired => 'Inserisci lo slug';

  @override
  String get companySlugInvalid =>
      'Formato slug non valido. Usa solo lettere minuscole, numeri e trattini';

  @override
  String get createCompanyButton => 'Crea azienda';

  @override
  String get companiesLoadRetryButton => 'Riprova';

  @override
  String get companySelectorTitle => 'Seleziona azienda';

  @override
  String get companySelectorSubtitle =>
      'Scegli l\'azienda con cui vuoi lavorare';

  @override
  String get companySelectorEmpty => 'Nessuna azienda disponibile';

  @override
  String dashboardActiveRole(String roleLabel) {
    return 'Ruolo: $roleLabel';
  }

  @override
  String dashboardCompanyWelcome(String companyName) {
    return 'Azienda: $companyName';
  }

  @override
  String dashboardCompanySlug(String slug) {
    return 'Slug: $slug';
  }

  @override
  String get genericError => 'Si è verificato un errore. Riprova.';

  @override
  String get resetPasswordSuccessMessage =>
      'Se l\'email è registrata, riceverai un link per reimpostare la password.';

  @override
  String get updatePasswordTitle => 'Nuova password';

  @override
  String get updatePasswordSubtitle =>
      'Scegli una nuova password per il tuo account';

  @override
  String get updatePasswordButton => 'Aggiorna password';

  @override
  String get updatePasswordSuccessMessage =>
      'Password aggiornata. Accedi con le nuove credenziali.';
}
