import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('it')];

  /// No description provided for @appTitle.
  ///
  /// In it, this message translates to:
  /// **'Project Atlas'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Inserisci le tue credenziali per continuare'**
  String get loginSubtitle;

  /// No description provided for @signupTitle.
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get signupTitle;

  /// No description provided for @signupSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Crea un account per iniziare'**
  String get signupSubtitle;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In it, this message translates to:
  /// **'Recupera password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la tua email per ricevere il link di reset'**
  String get forgotPasswordSubtitle;

  /// No description provided for @emailLabel.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In it, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @loginButton.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get loginButton;

  /// No description provided for @signupButton.
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get signupButton;

  /// No description provided for @forgotPasswordButton.
  ///
  /// In it, this message translates to:
  /// **'Invia link di reset'**
  String get forgotPasswordButton;

  /// No description provided for @goToSignup.
  ///
  /// In it, this message translates to:
  /// **'Non hai un account? Registrati'**
  String get goToSignup;

  /// No description provided for @goToLogin.
  ///
  /// In it, this message translates to:
  /// **'Hai già un account? Accedi'**
  String get goToLogin;

  /// No description provided for @goToForgotPassword.
  ///
  /// In it, this message translates to:
  /// **'Password dimenticata?'**
  String get goToForgotPassword;

  /// No description provided for @dashboardTitle.
  ///
  /// In it, this message translates to:
  /// **'Dashboard'**
  String get dashboardTitle;

  /// No description provided for @dashboardWelcome.
  ///
  /// In it, this message translates to:
  /// **'Benvenuto in Project Atlas'**
  String get dashboardWelcome;

  /// No description provided for @dashboardNoActiveCompany.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda attiva. Seleziona un\'azienda per continuare.'**
  String get dashboardNoActiveCompany;

  /// No description provided for @dashboardMembersTitle.
  ///
  /// In it, this message translates to:
  /// **'Membri'**
  String get dashboardMembersTitle;

  /// No description provided for @dashboardMembersLoading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento membri...'**
  String get dashboardMembersLoading;

  /// No description provided for @dashboardMembersError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento membri non riuscito. Riprova.'**
  String get dashboardMembersError;

  /// No description provided for @dashboardMembersRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get dashboardMembersRetry;

  /// No description provided for @dashboardMemberCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, =0{Nessun membro} =1{1 membro} other{{count} membri}}'**
  String dashboardMemberCount(int count);

  /// No description provided for @dashboardCashTitle.
  ///
  /// In it, this message translates to:
  /// **'Riepilogo economico'**
  String get dashboardCashTitle;

  /// No description provided for @dashboardCashLoading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento riepilogo economico...'**
  String get dashboardCashLoading;

  /// No description provided for @dashboardCashError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento riepilogo economico non riuscito. Riprova.'**
  String get dashboardCashError;

  /// No description provided for @dashboardCashRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get dashboardCashRetry;

  /// No description provided for @dashboardCashEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun movimento ancora'**
  String get dashboardCashEmpty;

  /// No description provided for @dashboardCashTotalSection.
  ///
  /// In it, this message translates to:
  /// **'Totale'**
  String get dashboardCashTotalSection;

  /// No description provided for @dashboardCashMonthSection.
  ///
  /// In it, this message translates to:
  /// **'Mese corrente'**
  String get dashboardCashMonthSection;

  /// No description provided for @dashboardCashIncome.
  ///
  /// In it, this message translates to:
  /// **'Entrate'**
  String get dashboardCashIncome;

  /// No description provided for @dashboardCashExpense.
  ///
  /// In it, this message translates to:
  /// **'Uscite'**
  String get dashboardCashExpense;

  /// No description provided for @dashboardCashBalance.
  ///
  /// In it, this message translates to:
  /// **'Saldo'**
  String get dashboardCashBalance;

  /// No description provided for @dashboardCashMovements.
  ///
  /// In it, this message translates to:
  /// **'Movimenti'**
  String get dashboardCashMovements;

  /// No description provided for @dashboardCashSeeTransactions.
  ///
  /// In it, this message translates to:
  /// **'Vedi movimenti'**
  String get dashboardCashSeeTransactions;

  /// No description provided for @logoutButton.
  ///
  /// In it, this message translates to:
  /// **'Esci'**
  String get logoutButton;

  /// No description provided for @navDashboard.
  ///
  /// In it, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navClients.
  ///
  /// In it, this message translates to:
  /// **'Clienti'**
  String get navClients;

  /// No description provided for @navTransactions.
  ///
  /// In it, this message translates to:
  /// **'Movimenti'**
  String get navTransactions;

  /// No description provided for @navDocuments.
  ///
  /// In it, this message translates to:
  /// **'Documenti'**
  String get navDocuments;

  /// No description provided for @navSettings.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get navSettings;

  /// No description provided for @cancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get save;

  /// No description provided for @documentsTitle.
  ///
  /// In it, this message translates to:
  /// **'Documenti'**
  String get documentsTitle;

  /// No description provided for @documentsEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun documento ancora. Carica il primo documento per iniziare.'**
  String get documentsEmpty;

  /// No description provided for @documentsLoadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento documenti non riuscito. Riprova.'**
  String get documentsLoadError;

  /// No description provided for @documentsRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get documentsRetry;

  /// No description provided for @documentsUpload.
  ///
  /// In it, this message translates to:
  /// **'Carica documento'**
  String get documentsUpload;

  /// No description provided for @documentsUploadConfirm.
  ///
  /// In it, this message translates to:
  /// **'Carica'**
  String get documentsUploadConfirm;

  /// No description provided for @documentsUploadSuccess.
  ///
  /// In it, this message translates to:
  /// **'Documento caricato.'**
  String get documentsUploadSuccess;

  /// No description provided for @documentsUploadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento documento non riuscito. Riprova.'**
  String get documentsUploadError;

  /// No description provided for @documentTitleLabel.
  ///
  /// In it, this message translates to:
  /// **'Titolo'**
  String get documentTitleLabel;

  /// No description provided for @documentOpen.
  ///
  /// In it, this message translates to:
  /// **'Apri'**
  String get documentOpen;

  /// No description provided for @documentOpenFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire il documento.'**
  String get documentOpenFailed;

  /// No description provided for @documentRename.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get documentRename;

  /// No description provided for @documentRenameSuccess.
  ///
  /// In it, this message translates to:
  /// **'Titolo aggiornato.'**
  String get documentRenameSuccess;

  /// No description provided for @documentRenameError.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento titolo non riuscito. Riprova.'**
  String get documentRenameError;

  /// No description provided for @documentArchive.
  ///
  /// In it, this message translates to:
  /// **'Archivia'**
  String get documentArchive;

  /// No description provided for @documentRestore.
  ///
  /// In it, this message translates to:
  /// **'Ripristina'**
  String get documentRestore;

  /// No description provided for @documentArchived.
  ///
  /// In it, this message translates to:
  /// **'Archiviato'**
  String get documentArchived;

  /// No description provided for @documentArchiveSuccess.
  ///
  /// In it, this message translates to:
  /// **'Documento archiviato.'**
  String get documentArchiveSuccess;

  /// No description provided for @documentRestoreSuccess.
  ///
  /// In it, this message translates to:
  /// **'Documento ripristinato.'**
  String get documentRestoreSuccess;

  /// No description provided for @documentArchiveError.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento archivio non riuscito. Riprova.'**
  String get documentArchiveError;

  /// No description provided for @documentReadOnlyMessage.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per caricare o modificare i documenti. Puoi solo visualizzarli e aprirli.'**
  String get documentReadOnlyMessage;

  /// No description provided for @documentManageLinks.
  ///
  /// In it, this message translates to:
  /// **'Gestisci collegamenti'**
  String get documentManageLinks;

  /// No description provided for @documentLinksClient.
  ///
  /// In it, this message translates to:
  /// **'Cliente'**
  String get documentLinksClient;

  /// No description provided for @documentLinksTransaction.
  ///
  /// In it, this message translates to:
  /// **'Movimento'**
  String get documentLinksTransaction;

  /// No description provided for @documentLinksNoClient.
  ///
  /// In it, this message translates to:
  /// **'Nessun cliente'**
  String get documentLinksNoClient;

  /// No description provided for @documentLinksNoTransaction.
  ///
  /// In it, this message translates to:
  /// **'Nessun movimento'**
  String get documentLinksNoTransaction;

  /// No description provided for @documentLinksSave.
  ///
  /// In it, this message translates to:
  /// **'Salva collegamenti'**
  String get documentLinksSave;

  /// No description provided for @documentLinksSuccess.
  ///
  /// In it, this message translates to:
  /// **'Collegamenti aggiornati.'**
  String get documentLinksSuccess;

  /// No description provided for @documentLinksError.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento collegamenti non riuscito. Riprova.'**
  String get documentLinksError;

  /// No description provided for @documentLinksSearchClient.
  ///
  /// In it, this message translates to:
  /// **'Cerca cliente'**
  String get documentLinksSearchClient;

  /// No description provided for @documentLinksSearchTransaction.
  ///
  /// In it, this message translates to:
  /// **'Cerca movimento'**
  String get documentLinksSearchTransaction;

  /// No description provided for @documentLinksEmptyClients.
  ///
  /// In it, this message translates to:
  /// **'Nessun cliente disponibile.'**
  String get documentLinksEmptyClients;

  /// No description provided for @documentLinksEmptyTransactions.
  ///
  /// In it, this message translates to:
  /// **'Nessun movimento disponibile.'**
  String get documentLinksEmptyTransactions;

  /// No description provided for @documentDeletePermanently.
  ///
  /// In it, this message translates to:
  /// **'Elimina definitivamente'**
  String get documentDeletePermanently;

  /// No description provided for @documentDeleteConfirmTitle.
  ///
  /// In it, this message translates to:
  /// **'Elimina definitivamente'**
  String get documentDeleteConfirmTitle;

  /// No description provided for @documentDeleteIrreversible.
  ///
  /// In it, this message translates to:
  /// **'Questa operazione è irreversibile. Il documento e il file associato verranno eliminati.'**
  String get documentDeleteIrreversible;

  /// No description provided for @documentDeleteConfirmAction.
  ///
  /// In it, this message translates to:
  /// **'Elimina definitivamente'**
  String get documentDeleteConfirmAction;

  /// No description provided for @documentDeleteSuccess.
  ///
  /// In it, this message translates to:
  /// **'Documento eliminato.'**
  String get documentDeleteSuccess;

  /// No description provided for @documentDeleteError.
  ///
  /// In it, this message translates to:
  /// **'Eliminazione documento non riuscita. Riprova.'**
  String get documentDeleteError;

  /// No description provided for @documentDeleteIncomplete.
  ///
  /// In it, this message translates to:
  /// **'Eliminazione incompleta. Il file è stato rimosso ma i dati restano. Riprova.'**
  String get documentDeleteIncomplete;

  /// No description provided for @documentLinkedClient.
  ///
  /// In it, this message translates to:
  /// **'Cliente: {name}'**
  String documentLinkedClient(String name);

  /// No description provided for @documentLinkedTransaction.
  ///
  /// In it, this message translates to:
  /// **'Movimento: {summary}'**
  String documentLinkedTransaction(String summary);

  /// No description provided for @customersTitle.
  ///
  /// In it, this message translates to:
  /// **'Clienti'**
  String get customersTitle;

  /// No description provided for @customersSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Anagrafica clienti dell\'azienda attiva'**
  String get customersSubtitle;

  /// No description provided for @customersNoActiveCompany.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda attiva. Seleziona un\'azienda per continuare.'**
  String get customersNoActiveCompany;

  /// No description provided for @customersEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun cliente ancora. Aggiungi il primo cliente per iniziare.'**
  String get customersEmpty;

  /// No description provided for @customersLoadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento clienti non riuscito. Riprova.'**
  String get customersLoadError;

  /// No description provided for @customersRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get customersRetry;

  /// No description provided for @customersNewButton.
  ///
  /// In it, this message translates to:
  /// **'Nuovo cliente'**
  String get customersNewButton;

  /// No description provided for @customersImportButton.
  ///
  /// In it, this message translates to:
  /// **'Importa clienti'**
  String get customersImportButton;

  /// No description provided for @customersImportTitle.
  ///
  /// In it, this message translates to:
  /// **'Importa clienti'**
  String get customersImportTitle;

  /// No description provided for @customersImportForbidden.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per importare clienti.'**
  String get customersImportForbidden;

  /// No description provided for @customersImportIntro.
  ///
  /// In it, this message translates to:
  /// **'Importa un elenco clienti da file CSV o Excel nell\'azienda attiva.'**
  String get customersImportIntro;

  /// No description provided for @customersImportFieldsNotice.
  ///
  /// In it, this message translates to:
  /// **'Questa versione importa soltanto: Nome o ragione sociale, Email, Telefono, Note.'**
  String get customersImportFieldsNotice;

  /// No description provided for @customersImportLimits.
  ///
  /// In it, this message translates to:
  /// **'Limiti: file fino a 2 MB, massimo 500 righe dati, massimo 20 fogli Excel, un foglio alla volta.'**
  String get customersImportLimits;

  /// No description provided for @customersImportPickFile.
  ///
  /// In it, this message translates to:
  /// **'Seleziona file CSV o XLSX'**
  String get customersImportPickFile;

  /// No description provided for @customersImportPickSheet.
  ///
  /// In it, this message translates to:
  /// **'Scegli il foglio da importare'**
  String get customersImportPickSheet;

  /// No description provided for @customersImportMappingTitle.
  ///
  /// In it, this message translates to:
  /// **'Associa le colonne'**
  String get customersImportMappingTitle;

  /// No description provided for @customersImportMappingHint.
  ///
  /// In it, this message translates to:
  /// **'Il campo Nome o ragione sociale è obbligatorio. Ogni campo può essere associato a una sola colonna.'**
  String get customersImportMappingHint;

  /// No description provided for @customersImportFieldName.
  ///
  /// In it, this message translates to:
  /// **'Nome o ragione sociale'**
  String get customersImportFieldName;

  /// No description provided for @customersImportFieldEmail.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get customersImportFieldEmail;

  /// No description provided for @customersImportFieldPhone.
  ///
  /// In it, this message translates to:
  /// **'Telefono'**
  String get customersImportFieldPhone;

  /// No description provided for @customersImportFieldNotes.
  ///
  /// In it, this message translates to:
  /// **'Note'**
  String get customersImportFieldNotes;

  /// No description provided for @customersImportFieldIgnore.
  ///
  /// In it, this message translates to:
  /// **'Ignora'**
  String get customersImportFieldIgnore;

  /// No description provided for @customersImportContinue.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get customersImportContinue;

  /// No description provided for @customersImportSummaryTitle.
  ///
  /// In it, this message translates to:
  /// **'Riepilogo analisi'**
  String get customersImportSummaryTitle;

  /// No description provided for @customersImportSummaryRead.
  ///
  /// In it, this message translates to:
  /// **'Righe lette: {count}'**
  String customersImportSummaryRead(int count);

  /// No description provided for @customersImportSummaryValid.
  ///
  /// In it, this message translates to:
  /// **'Clienti validi: {count}'**
  String customersImportSummaryValid(int count);

  /// No description provided for @customersImportSummaryDuplicates.
  ///
  /// In it, this message translates to:
  /// **'Duplicati esclusi: {count}'**
  String customersImportSummaryDuplicates(int count);

  /// No description provided for @customersImportSummaryErrors.
  ///
  /// In it, this message translates to:
  /// **'Righe con errori: {count}'**
  String customersImportSummaryErrors(int count);

  /// No description provided for @customersImportSummaryEmpty.
  ///
  /// In it, this message translates to:
  /// **'Righe vuote ignorate: {count}'**
  String customersImportSummaryEmpty(int count);

  /// No description provided for @customersImportSummaryWarnings.
  ///
  /// In it, this message translates to:
  /// **'Avvisi: {count}'**
  String customersImportSummaryWarnings(int count);

  /// No description provided for @customersImportPreviewTitle.
  ///
  /// In it, this message translates to:
  /// **'Anteprima (prime 20 righe)'**
  String get customersImportPreviewTitle;

  /// No description provided for @customersImportPreviewRowTitle.
  ///
  /// In it, this message translates to:
  /// **'Riga {row} · {status}'**
  String customersImportPreviewRowTitle(int row, String status);

  /// No description provided for @customersImportPreviewStatusError.
  ///
  /// In it, this message translates to:
  /// **'errore'**
  String get customersImportPreviewStatusError;

  /// No description provided for @customersImportPreviewStatusDuplicate.
  ///
  /// In it, this message translates to:
  /// **'duplicato'**
  String get customersImportPreviewStatusDuplicate;

  /// No description provided for @customersImportPreviewStatusOk.
  ///
  /// In it, this message translates to:
  /// **'ok'**
  String get customersImportPreviewStatusOk;

  /// No description provided for @customersImportIssueWithRow.
  ///
  /// In it, this message translates to:
  /// **'Riga {row} — {message}'**
  String customersImportIssueWithRow(int row, String message);

  /// No description provided for @customersImportIssueLeadingZeroRisk.
  ///
  /// In it, this message translates to:
  /// **'Questa cella numerica potrebbe aver perso uno zero iniziale.'**
  String get customersImportIssueLeadingZeroRisk;

  /// No description provided for @customersImportIssueDuplicateEmailInFile.
  ///
  /// In it, this message translates to:
  /// **'Email duplicata nel file: la riga verrà esclusa.'**
  String get customersImportIssueDuplicateEmailInFile;

  /// No description provided for @customersImportIssueDuplicateEmailInDatabase.
  ///
  /// In it, this message translates to:
  /// **'Email già presente tra i clienti dell\'azienda: la riga verrà esclusa.'**
  String get customersImportIssueDuplicateEmailInDatabase;

  /// No description provided for @customersImportIssueMissingName.
  ///
  /// In it, this message translates to:
  /// **'Nome o ragione sociale mancante.'**
  String get customersImportIssueMissingName;

  /// No description provided for @customersImportIssueInvalidEmail.
  ///
  /// In it, this message translates to:
  /// **'Indirizzo email non valido.'**
  String get customersImportIssueInvalidEmail;

  /// No description provided for @customersImportIssueNameTooLong.
  ///
  /// In it, this message translates to:
  /// **'Nome o ragione sociale troppo lungo.'**
  String get customersImportIssueNameTooLong;

  /// No description provided for @customersImportIssueEmailTooLong.
  ///
  /// In it, this message translates to:
  /// **'Indirizzo email troppo lungo.'**
  String get customersImportIssueEmailTooLong;

  /// No description provided for @customersImportIssuePhoneTooLong.
  ///
  /// In it, this message translates to:
  /// **'Numero di telefono troppo lungo.'**
  String get customersImportIssuePhoneTooLong;

  /// No description provided for @customersImportIssueNotesTooLong.
  ///
  /// In it, this message translates to:
  /// **'Note troppo lunghe.'**
  String get customersImportIssueNotesTooLong;

  /// No description provided for @customersImportIssueFormulaNotSupported.
  ///
  /// In it, this message translates to:
  /// **'Le formule Excel non sono supportate in questo campo.'**
  String get customersImportIssueFormulaNotSupported;

  /// No description provided for @customersImportIssueInvalidCellType.
  ///
  /// In it, this message translates to:
  /// **'Tipo di cella non supportato.'**
  String get customersImportIssueInvalidCellType;

  /// No description provided for @customersImportIssueDuplicateNameWarning.
  ///
  /// In it, this message translates to:
  /// **'Esiste già una riga con lo stesso nome: controlla che non sia un duplicato.'**
  String get customersImportIssueDuplicateNameWarning;

  /// No description provided for @customersImportIssueGeneric.
  ///
  /// In it, this message translates to:
  /// **'Problema nella riga.'**
  String get customersImportIssueGeneric;

  /// No description provided for @customersImportConfirm.
  ///
  /// In it, this message translates to:
  /// **'Conferma importazione'**
  String get customersImportConfirm;

  /// No description provided for @customersImportResultTitle.
  ///
  /// In it, this message translates to:
  /// **'Importazione completata'**
  String get customersImportResultTitle;

  /// No description provided for @customersImportResultInserted.
  ///
  /// In it, this message translates to:
  /// **'Clienti inseriti: {count}'**
  String customersImportResultInserted(int count);

  /// No description provided for @customersImportResultSkipped.
  ///
  /// In it, this message translates to:
  /// **'Duplicati esclusi dal server: {count}'**
  String customersImportResultSkipped(int count);

  /// No description provided for @customersImportBackToList.
  ///
  /// In it, this message translates to:
  /// **'Torna ai clienti'**
  String get customersImportBackToList;

  /// No description provided for @customerNewTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuovo cliente'**
  String get customerNewTitle;

  /// No description provided for @customerEditTitle.
  ///
  /// In it, this message translates to:
  /// **'Modifica cliente'**
  String get customerEditTitle;

  /// No description provided for @customerNotFound.
  ///
  /// In it, this message translates to:
  /// **'Cliente non trovato.'**
  String get customerNotFound;

  /// No description provided for @customerReadOnlyMessage.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per modificare i clienti. Contatta un proprietario, un amministratore o un manager.'**
  String get customerReadOnlyMessage;

  /// No description provided for @customerNameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome'**
  String get customerNameLabel;

  /// No description provided for @customerNameRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il nome del cliente'**
  String get customerNameRequired;

  /// No description provided for @customerEmailLabel.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get customerEmailLabel;

  /// No description provided for @customerPhoneLabel.
  ///
  /// In it, this message translates to:
  /// **'Telefono'**
  String get customerPhoneLabel;

  /// No description provided for @customerNotesLabel.
  ///
  /// In it, this message translates to:
  /// **'Note'**
  String get customerNotesLabel;

  /// No description provided for @customerSaveButton.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get customerSaveButton;

  /// No description provided for @customerCreateSuccess.
  ///
  /// In it, this message translates to:
  /// **'Cliente creato correttamente.'**
  String get customerCreateSuccess;

  /// No description provided for @customerUpdateSuccess.
  ///
  /// In it, this message translates to:
  /// **'Cliente aggiornato correttamente.'**
  String get customerUpdateSuccess;

  /// No description provided for @transactionsTitle.
  ///
  /// In it, this message translates to:
  /// **'Movimenti'**
  String get transactionsTitle;

  /// No description provided for @transactionsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Entrate e uscite dell\'azienda attiva'**
  String get transactionsSubtitle;

  /// No description provided for @transactionsNoActiveCompany.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda attiva. Seleziona un\'azienda per continuare.'**
  String get transactionsNoActiveCompany;

  /// No description provided for @transactionsEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun movimento ancora. Aggiungi il primo movimento per iniziare.'**
  String get transactionsEmpty;

  /// No description provided for @transactionsFilterEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun movimento corrisponde ai filtri selezionati.'**
  String get transactionsFilterEmpty;

  /// No description provided for @transactionsResultsCount.
  ///
  /// In it, this message translates to:
  /// **'Risultati trovati: {count}'**
  String transactionsResultsCount(int count);

  /// No description provided for @transactionsFiltersTitle.
  ///
  /// In it, this message translates to:
  /// **'Filtri'**
  String get transactionsFiltersTitle;

  /// No description provided for @transactionsFilterFromDate.
  ///
  /// In it, this message translates to:
  /// **'Dal'**
  String get transactionsFilterFromDate;

  /// No description provided for @transactionsFilterToDate.
  ///
  /// In it, this message translates to:
  /// **'Al'**
  String get transactionsFilterToDate;

  /// No description provided for @transactionsFilterPickDate.
  ///
  /// In it, this message translates to:
  /// **'Scegli data'**
  String get transactionsFilterPickDate;

  /// No description provided for @transactionsFilterKindAll.
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get transactionsFilterKindAll;

  /// No description provided for @transactionsFilterClientAll.
  ///
  /// In it, this message translates to:
  /// **'Tutti i clienti'**
  String get transactionsFilterClientAll;

  /// No description provided for @transactionsFilterDescriptionHint.
  ///
  /// In it, this message translates to:
  /// **'Cerca nella descrizione'**
  String get transactionsFilterDescriptionHint;

  /// No description provided for @transactionsFilterClear.
  ///
  /// In it, this message translates to:
  /// **'Cancella filtri'**
  String get transactionsFilterClear;

  /// No description provided for @transactionsLoadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento movimenti non riuscito. Riprova.'**
  String get transactionsLoadError;

  /// No description provided for @transactionsRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get transactionsRetry;

  /// No description provided for @transactionsNewButton.
  ///
  /// In it, this message translates to:
  /// **'Nuovo movimento'**
  String get transactionsNewButton;

  /// No description provided for @transactionsImportButton.
  ///
  /// In it, this message translates to:
  /// **'Importa movimenti'**
  String get transactionsImportButton;

  /// No description provided for @transactionsImportTitle.
  ///
  /// In it, this message translates to:
  /// **'Importa movimenti'**
  String get transactionsImportTitle;

  /// No description provided for @transactionsImportForbidden.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per importare movimenti.'**
  String get transactionsImportForbidden;

  /// No description provided for @transactionsImportIntro.
  ///
  /// In it, this message translates to:
  /// **'Importa i movimenti di cassa da un file CSV o Excel nell\'azienda attiva.'**
  String get transactionsImportIntro;

  /// No description provided for @transactionsImportFieldsNotice.
  ///
  /// In it, this message translates to:
  /// **'Questa versione importa soltanto: Data, Descrizione, Importo (colonna con segno oppure Dare e Avere), Riferimento, Note. Il verso del movimento viene dedotto dal segno dell\'importo o dalla colonna Dare/Avere.'**
  String get transactionsImportFieldsNotice;

  /// No description provided for @transactionsImportLimits.
  ///
  /// In it, this message translates to:
  /// **'Limiti: file fino a 2 MB, massimo 500 righe dati, massimo 20 fogli Excel, un foglio alla volta.'**
  String get transactionsImportLimits;

  /// No description provided for @transactionsImportDeferredNotice.
  ///
  /// In it, this message translates to:
  /// **'Non sono previsti in questa versione: collegamento alle API bancarie, calcoli fiscali e annullamento di un\'importazione.'**
  String get transactionsImportDeferredNotice;

  /// No description provided for @transactionsImportPickFile.
  ///
  /// In it, this message translates to:
  /// **'Seleziona file CSV o XLSX'**
  String get transactionsImportPickFile;

  /// No description provided for @transactionsImportPickSheet.
  ///
  /// In it, this message translates to:
  /// **'Scegli il foglio da importare'**
  String get transactionsImportPickSheet;

  /// No description provided for @transactionsImportSheetRows.
  ///
  /// In it, this message translates to:
  /// **'{count} righe dati'**
  String transactionsImportSheetRows(int count);

  /// No description provided for @transactionsImportMappingTitle.
  ///
  /// In it, this message translates to:
  /// **'Associa le colonne'**
  String get transactionsImportMappingTitle;

  /// No description provided for @transactionsImportMappingHint.
  ///
  /// In it, this message translates to:
  /// **'Data e Descrizione sono obbligatorie. Per l\'importo scegli una colonna con segno oppure la coppia Dare e Avere. Ogni campo può essere associato a una sola colonna.'**
  String get transactionsImportMappingHint;

  /// No description provided for @transactionsImportFieldDate.
  ///
  /// In it, this message translates to:
  /// **'Data'**
  String get transactionsImportFieldDate;

  /// No description provided for @transactionsImportFieldDescription.
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get transactionsImportFieldDescription;

  /// No description provided for @transactionsImportFieldSignedAmount.
  ///
  /// In it, this message translates to:
  /// **'Importo con segno'**
  String get transactionsImportFieldSignedAmount;

  /// No description provided for @transactionsImportFieldDebit.
  ///
  /// In it, this message translates to:
  /// **'Dare (uscite)'**
  String get transactionsImportFieldDebit;

  /// No description provided for @transactionsImportFieldCredit.
  ///
  /// In it, this message translates to:
  /// **'Avere (entrate)'**
  String get transactionsImportFieldCredit;

  /// No description provided for @transactionsImportFieldReference.
  ///
  /// In it, this message translates to:
  /// **'Riferimento'**
  String get transactionsImportFieldReference;

  /// No description provided for @transactionsImportFieldNotes.
  ///
  /// In it, this message translates to:
  /// **'Note'**
  String get transactionsImportFieldNotes;

  /// No description provided for @transactionsImportFieldIgnore.
  ///
  /// In it, this message translates to:
  /// **'Ignora'**
  String get transactionsImportFieldIgnore;

  /// No description provided for @transactionsImportContinue.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get transactionsImportContinue;

  /// No description provided for @transactionsImportBack.
  ///
  /// In it, this message translates to:
  /// **'Indietro'**
  String get transactionsImportBack;

  /// No description provided for @transactionsImportFormatTitle.
  ///
  /// In it, this message translates to:
  /// **'Scegli come leggere i valori'**
  String get transactionsImportFormatTitle;

  /// No description provided for @transactionsImportFormatHint.
  ///
  /// In it, this message translates to:
  /// **'Alcuni valori del file possono essere letti in più modi. Nessuna interpretazione viene scelta automaticamente: indica tu il formato corretto.'**
  String get transactionsImportFormatHint;

  /// No description provided for @transactionsImportNumberFormatLabel.
  ///
  /// In it, this message translates to:
  /// **'Separatore decimale'**
  String get transactionsImportNumberFormatLabel;

  /// No description provided for @transactionsImportNumberFormatAuto.
  ///
  /// In it, this message translates to:
  /// **'Non specificato'**
  String get transactionsImportNumberFormatAuto;

  /// No description provided for @transactionsImportNumberFormatComma.
  ///
  /// In it, this message translates to:
  /// **'Virgola: 1.234,56'**
  String get transactionsImportNumberFormatComma;

  /// No description provided for @transactionsImportNumberFormatDot.
  ///
  /// In it, this message translates to:
  /// **'Punto: 1,234.56'**
  String get transactionsImportNumberFormatDot;

  /// No description provided for @transactionsImportNumberFormatRequired.
  ///
  /// In it, this message translates to:
  /// **'Il file contiene importi ambigui: scegli il separatore decimale.'**
  String get transactionsImportNumberFormatRequired;

  /// No description provided for @transactionsImportDateFormatLabel.
  ///
  /// In it, this message translates to:
  /// **'Ordine dei campi data'**
  String get transactionsImportDateFormatLabel;

  /// No description provided for @transactionsImportDateFormatAuto.
  ///
  /// In it, this message translates to:
  /// **'Non specificato'**
  String get transactionsImportDateFormatAuto;

  /// No description provided for @transactionsImportDateFormatDmy.
  ///
  /// In it, this message translates to:
  /// **'Giorno/Mese/Anno'**
  String get transactionsImportDateFormatDmy;

  /// No description provided for @transactionsImportDateFormatMdy.
  ///
  /// In it, this message translates to:
  /// **'Mese/Giorno/Anno'**
  String get transactionsImportDateFormatMdy;

  /// No description provided for @transactionsImportDateFormatYmd.
  ///
  /// In it, this message translates to:
  /// **'Anno-Mese-Giorno'**
  String get transactionsImportDateFormatYmd;

  /// No description provided for @transactionsImportDateFormatRequired.
  ///
  /// In it, this message translates to:
  /// **'Il file contiene date ambigue: scegli l\'ordine di giorno e mese.'**
  String get transactionsImportDateFormatRequired;

  /// No description provided for @transactionsImportSummaryTitle.
  ///
  /// In it, this message translates to:
  /// **'Riepilogo analisi'**
  String get transactionsImportSummaryTitle;

  /// No description provided for @transactionsImportSummaryRead.
  ///
  /// In it, this message translates to:
  /// **'Righe lette: {count}'**
  String transactionsImportSummaryRead(int count);

  /// No description provided for @transactionsImportSummaryValid.
  ///
  /// In it, this message translates to:
  /// **'Movimenti validi: {count}'**
  String transactionsImportSummaryValid(int count);

  /// No description provided for @transactionsImportSummaryInvalid.
  ///
  /// In it, this message translates to:
  /// **'Righe con errori: {count}'**
  String transactionsImportSummaryInvalid(int count);

  /// No description provided for @transactionsImportSummaryPossibleDuplicates.
  ///
  /// In it, this message translates to:
  /// **'Possibili duplicati segnalati: {count}'**
  String transactionsImportSummaryPossibleDuplicates(int count);

  /// No description provided for @transactionsImportSummaryDuplicatesInFile.
  ///
  /// In it, this message translates to:
  /// **'Duplicati nel file esclusi: {count}'**
  String transactionsImportSummaryDuplicatesInFile(int count);

  /// No description provided for @transactionsImportSummarySelected.
  ///
  /// In it, this message translates to:
  /// **'Righe da importare: {count}'**
  String transactionsImportSummarySelected(int count);

  /// No description provided for @transactionsImportSummaryEmpty.
  ///
  /// In it, this message translates to:
  /// **'Righe vuote ignorate: {count}'**
  String transactionsImportSummaryEmpty(int count);

  /// No description provided for @transactionsImportSummaryWarnings.
  ///
  /// In it, this message translates to:
  /// **'Avvisi: {count}'**
  String transactionsImportSummaryWarnings(int count);

  /// No description provided for @transactionsImportPreviewTitle.
  ///
  /// In it, this message translates to:
  /// **'Anteprima (prime 20 righe)'**
  String get transactionsImportPreviewTitle;

  /// No description provided for @transactionsImportPreviewRowTitle.
  ///
  /// In it, this message translates to:
  /// **'Riga {row} · {status}'**
  String transactionsImportPreviewRowTitle(int row, String status);

  /// No description provided for @transactionsImportPreviewRowDetail.
  ///
  /// In it, this message translates to:
  /// **'{date} · {kind} {amount} € · {description}'**
  String transactionsImportPreviewRowDetail(
    String date,
    String kind,
    String amount,
    String description,
  );

  /// No description provided for @transactionsImportPreviewStatusOk.
  ///
  /// In it, this message translates to:
  /// **'ok'**
  String get transactionsImportPreviewStatusOk;

  /// No description provided for @transactionsImportPreviewStatusError.
  ///
  /// In it, this message translates to:
  /// **'errore'**
  String get transactionsImportPreviewStatusError;

  /// No description provided for @transactionsImportPreviewStatusPossibleDuplicate.
  ///
  /// In it, this message translates to:
  /// **'possibile duplicato'**
  String get transactionsImportPreviewStatusPossibleDuplicate;

  /// No description provided for @transactionsImportPreviewStatusDuplicateInFile.
  ///
  /// In it, this message translates to:
  /// **'duplicato nel file'**
  String get transactionsImportPreviewStatusDuplicateInFile;

  /// No description provided for @transactionsImportIncludeDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Importa comunque questa riga'**
  String get transactionsImportIncludeDuplicate;

  /// No description provided for @transactionsImportIssueWithRow.
  ///
  /// In it, this message translates to:
  /// **'Riga {row} — {message}'**
  String transactionsImportIssueWithRow(int row, String message);

  /// No description provided for @transactionsImportIssueDateMissing.
  ///
  /// In it, this message translates to:
  /// **'Data mancante.'**
  String get transactionsImportIssueDateMissing;

  /// No description provided for @transactionsImportIssueDateInvalid.
  ///
  /// In it, this message translates to:
  /// **'Data non valida.'**
  String get transactionsImportIssueDateInvalid;

  /// No description provided for @transactionsImportIssueDateUnsupportedFormat.
  ///
  /// In it, this message translates to:
  /// **'Formato data non supportato. Usa AAAA-MM-GG oppure GG/MM/AAAA con anno a quattro cifre.'**
  String get transactionsImportIssueDateUnsupportedFormat;

  /// No description provided for @transactionsImportIssueNeedsDateFormat.
  ///
  /// In it, this message translates to:
  /// **'Giorno e mese sono ambigui: scegli l\'ordine dei campi data.'**
  String get transactionsImportIssueNeedsDateFormat;

  /// No description provided for @transactionsImportIssueAmountMissing.
  ///
  /// In it, this message translates to:
  /// **'Importo mancante.'**
  String get transactionsImportIssueAmountMissing;

  /// No description provided for @transactionsImportIssueAmountNotNumeric.
  ///
  /// In it, this message translates to:
  /// **'Importo non numerico.'**
  String get transactionsImportIssueAmountNotNumeric;

  /// No description provided for @transactionsImportIssueAmountZero.
  ///
  /// In it, this message translates to:
  /// **'L\'importo non può essere zero.'**
  String get transactionsImportIssueAmountZero;

  /// No description provided for @transactionsImportIssueAmountTooManyDecimals.
  ///
  /// In it, this message translates to:
  /// **'L\'importo ha più di due cifre decimali.'**
  String get transactionsImportIssueAmountTooManyDecimals;

  /// No description provided for @transactionsImportIssueAmountOutOfRange.
  ///
  /// In it, this message translates to:
  /// **'Importo fuori dai limiti consentiti.'**
  String get transactionsImportIssueAmountOutOfRange;

  /// No description provided for @transactionsImportIssueAmountSignNotAllowed.
  ///
  /// In it, this message translates to:
  /// **'Nelle colonne Dare e Avere il segno non è ammesso.'**
  String get transactionsImportIssueAmountSignNotAllowed;

  /// No description provided for @transactionsImportIssueAmountBothDebitAndCredit.
  ///
  /// In it, this message translates to:
  /// **'La riga valorizza sia Dare sia Avere.'**
  String get transactionsImportIssueAmountBothDebitAndCredit;

  /// No description provided for @transactionsImportIssueNeedsNumberFormat.
  ///
  /// In it, this message translates to:
  /// **'Separatore decimale ambiguo: scegli il formato degli importi.'**
  String get transactionsImportIssueNeedsNumberFormat;

  /// No description provided for @transactionsImportIssueDescriptionMissing.
  ///
  /// In it, this message translates to:
  /// **'Descrizione mancante.'**
  String get transactionsImportIssueDescriptionMissing;

  /// No description provided for @transactionsImportIssueDescriptionTooLong.
  ///
  /// In it, this message translates to:
  /// **'Descrizione troppo lunga (massimo 500 caratteri).'**
  String get transactionsImportIssueDescriptionTooLong;

  /// No description provided for @transactionsImportIssueNotesTooLong.
  ///
  /// In it, this message translates to:
  /// **'Note troppo lunghe (massimo 2000 caratteri).'**
  String get transactionsImportIssueNotesTooLong;

  /// No description provided for @transactionsImportIssueReferenceTooLong.
  ///
  /// In it, this message translates to:
  /// **'Riferimento troppo lungo (massimo 120 caratteri).'**
  String get transactionsImportIssueReferenceTooLong;

  /// No description provided for @transactionsImportIssueFormulaCell.
  ///
  /// In it, this message translates to:
  /// **'Le formule Excel non sono supportate in questo campo.'**
  String get transactionsImportIssueFormulaCell;

  /// No description provided for @transactionsImportIssueDuplicateInFile.
  ///
  /// In it, this message translates to:
  /// **'Riga già presente nel file: verrà importata una sola volta.'**
  String get transactionsImportIssueDuplicateInFile;

  /// No description provided for @transactionsImportIssuePossibleDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Esiste già un movimento simile in azienda: la riga è esclusa per sicurezza.'**
  String get transactionsImportIssuePossibleDuplicate;

  /// No description provided for @transactionsImportIssueDateMappingRequired.
  ///
  /// In it, this message translates to:
  /// **'Associa la colonna Data a una sola colonna del file.'**
  String get transactionsImportIssueDateMappingRequired;

  /// No description provided for @transactionsImportIssueDescriptionMappingRequired.
  ///
  /// In it, this message translates to:
  /// **'Associa la colonna Descrizione a una sola colonna del file.'**
  String get transactionsImportIssueDescriptionMappingRequired;

  /// No description provided for @transactionsImportIssueAmountMappingRequired.
  ///
  /// In it, this message translates to:
  /// **'Associa una colonna Importo con segno oppure la coppia Dare e Avere.'**
  String get transactionsImportIssueAmountMappingRequired;

  /// No description provided for @transactionsImportIssueFieldMappedMoreThanOnce.
  ///
  /// In it, this message translates to:
  /// **'Ogni campo può essere associato a una sola colonna.'**
  String get transactionsImportIssueFieldMappedMoreThanOnce;

  /// No description provided for @transactionsImportIssueFileTooLarge.
  ///
  /// In it, this message translates to:
  /// **'Il file supera il limite di 2 MB.'**
  String get transactionsImportIssueFileTooLarge;

  /// No description provided for @transactionsImportIssueTooManyRows.
  ///
  /// In it, this message translates to:
  /// **'Il file supera il limite di 500 righe dati.'**
  String get transactionsImportIssueTooManyRows;

  /// No description provided for @transactionsImportIssueTooManySheets.
  ///
  /// In it, this message translates to:
  /// **'Troppi fogli Excel (massimo 20).'**
  String get transactionsImportIssueTooManySheets;

  /// No description provided for @transactionsImportIssueGeneric.
  ///
  /// In it, this message translates to:
  /// **'Problema nella riga.'**
  String get transactionsImportIssueGeneric;

  /// No description provided for @transactionsImportConfirm.
  ///
  /// In it, this message translates to:
  /// **'Conferma importazione'**
  String get transactionsImportConfirm;

  /// No description provided for @transactionsImportInProgress.
  ///
  /// In it, this message translates to:
  /// **'Importazione in corso...'**
  String get transactionsImportInProgress;

  /// No description provided for @transactionsImportResultTitle.
  ///
  /// In it, this message translates to:
  /// **'Importazione completata'**
  String get transactionsImportResultTitle;

  /// No description provided for @transactionsImportResultImported.
  ///
  /// In it, this message translates to:
  /// **'Movimenti importati: {count}'**
  String transactionsImportResultImported(int count);

  /// No description provided for @transactionsImportResultSkippedInvalid.
  ///
  /// In it, this message translates to:
  /// **'Righe scartate dal server: {count}'**
  String transactionsImportResultSkippedInvalid(int count);

  /// No description provided for @transactionsImportResultSkippedDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Duplicati esclusi dal server: {count}'**
  String transactionsImportResultSkippedDuplicate(int count);

  /// No description provided for @transactionsImportBackToList.
  ///
  /// In it, this message translates to:
  /// **'Torna ai movimenti'**
  String get transactionsImportBackToList;

  /// No description provided for @transactionNewTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuovo movimento'**
  String get transactionNewTitle;

  /// No description provided for @transactionEditTitle.
  ///
  /// In it, this message translates to:
  /// **'Modifica movimento'**
  String get transactionEditTitle;

  /// No description provided for @transactionNotFound.
  ///
  /// In it, this message translates to:
  /// **'Movimento non trovato.'**
  String get transactionNotFound;

  /// No description provided for @transactionReadOnlyMessage.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per modificare i movimenti. Contatta un proprietario, un amministratore o un manager.'**
  String get transactionReadOnlyMessage;

  /// No description provided for @transactionKindLabel.
  ///
  /// In it, this message translates to:
  /// **'Tipo'**
  String get transactionKindLabel;

  /// No description provided for @transactionKindIncome.
  ///
  /// In it, this message translates to:
  /// **'Entrata'**
  String get transactionKindIncome;

  /// No description provided for @transactionKindExpense.
  ///
  /// In it, this message translates to:
  /// **'Uscita'**
  String get transactionKindExpense;

  /// No description provided for @transactionAmountLabel.
  ///
  /// In it, this message translates to:
  /// **'Importo (€)'**
  String get transactionAmountLabel;

  /// No description provided for @transactionAmountRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci l\'importo'**
  String get transactionAmountRequired;

  /// No description provided for @transactionAmountInvalid.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un importo valido maggiore di zero'**
  String get transactionAmountInvalid;

  /// No description provided for @transactionDateLabel.
  ///
  /// In it, this message translates to:
  /// **'Data movimento'**
  String get transactionDateLabel;

  /// No description provided for @transactionDescriptionLabel.
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get transactionDescriptionLabel;

  /// No description provided for @transactionDescriptionRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la descrizione'**
  String get transactionDescriptionRequired;

  /// No description provided for @transactionNotesLabel.
  ///
  /// In it, this message translates to:
  /// **'Note'**
  String get transactionNotesLabel;

  /// No description provided for @transactionClientLabel.
  ///
  /// In it, this message translates to:
  /// **'Cliente'**
  String get transactionClientLabel;

  /// No description provided for @transactionClientNone.
  ///
  /// In it, this message translates to:
  /// **'Nessun cliente'**
  String get transactionClientNone;

  /// No description provided for @transactionClientsLoading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento clienti...'**
  String get transactionClientsLoading;

  /// No description provided for @transactionClientsLoadError.
  ///
  /// In it, this message translates to:
  /// **'Clienti non disponibili. Puoi comunque salvare senza cliente.'**
  String get transactionClientsLoadError;

  /// No description provided for @transactionSaveButton.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get transactionSaveButton;

  /// No description provided for @transactionCreateSuccess.
  ///
  /// In it, this message translates to:
  /// **'Movimento creato correttamente.'**
  String get transactionCreateSuccess;

  /// No description provided for @transactionUpdateSuccess.
  ///
  /// In it, this message translates to:
  /// **'Movimento aggiornato correttamente.'**
  String get transactionUpdateSuccess;

  /// No description provided for @transactionCategoryLabel.
  ///
  /// In it, this message translates to:
  /// **'Categoria'**
  String get transactionCategoryLabel;

  /// No description provided for @transactionCategoryNone.
  ///
  /// In it, this message translates to:
  /// **'Nessuna categoria'**
  String get transactionCategoryNone;

  /// No description provided for @transactionCategoryArchived.
  ///
  /// In it, this message translates to:
  /// **'Archiviata'**
  String get transactionCategoryArchived;

  /// No description provided for @transactionCategoriesLoading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento categorie...'**
  String get transactionCategoriesLoading;

  /// No description provided for @transactionCategoriesLoadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento categorie non riuscito. Riprova.'**
  String get transactionCategoriesLoadError;

  /// No description provided for @transactionCategoriesEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessuna categoria disponibile per questo tipo.'**
  String get transactionCategoriesEmpty;

  /// No description provided for @transactionCategoriesManageLink.
  ///
  /// In it, this message translates to:
  /// **'Gestisci categorie'**
  String get transactionCategoriesManageLink;

  /// No description provided for @transactionCategoryInvalid.
  ///
  /// In it, this message translates to:
  /// **'La categoria selezionata non è valida per questo movimento.'**
  String get transactionCategoryInvalid;

  /// No description provided for @companySettingsTitle.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni azienda'**
  String get companySettingsTitle;

  /// No description provided for @companySettingsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Visualizza e aggiorna i dati dell\'azienda attiva'**
  String get companySettingsSubtitle;

  /// No description provided for @companySettingsNoActiveCompany.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda attiva. Seleziona un\'azienda per continuare.'**
  String get companySettingsNoActiveCompany;

  /// No description provided for @companySettingsReadOnlyMessage.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per modificare questa azienda. Contatta un proprietario o un amministratore.'**
  String get companySettingsReadOnlyMessage;

  /// No description provided for @companySettingsSaveButton.
  ///
  /// In it, this message translates to:
  /// **'Salva modifiche'**
  String get companySettingsSaveButton;

  /// No description provided for @companySettingsSaveSuccess.
  ///
  /// In it, this message translates to:
  /// **'Azienda aggiornata correttamente.'**
  String get companySettingsSaveSuccess;

  /// No description provided for @categoriesTitle.
  ///
  /// In it, this message translates to:
  /// **'Categorie'**
  String get categoriesTitle;

  /// No description provided for @categoriesSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Categorie operative di entrate e uscite (non fiscali).'**
  String get categoriesSubtitle;

  /// No description provided for @categoriesSettingsLinkSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Gestisci le categorie dei movimenti'**
  String get categoriesSettingsLinkSubtitle;

  /// No description provided for @teamTitle.
  ///
  /// In it, this message translates to:
  /// **'Team'**
  String get teamTitle;

  /// No description provided for @teamSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Membri e inviti dell\'azienda attiva.'**
  String get teamSubtitle;

  /// No description provided for @teamSettingsLinkSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Gestisci membri e inviti'**
  String get teamSettingsLinkSubtitle;

  /// No description provided for @teamNoActiveCompany.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda attiva. Seleziona un\'azienda per continuare.'**
  String get teamNoActiveCompany;

  /// No description provided for @teamReadOnlyMessage.
  ///
  /// In it, this message translates to:
  /// **'Puoi visualizzare i membri, ma solo proprietario e amministratore gestiscono inviti e ruoli.'**
  String get teamReadOnlyMessage;

  /// No description provided for @teamMembersSection.
  ///
  /// In it, this message translates to:
  /// **'Membri'**
  String get teamMembersSection;

  /// No description provided for @teamMembersEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun membro trovato.'**
  String get teamMembersEmpty;

  /// No description provided for @teamPendingInvitesSection.
  ///
  /// In it, this message translates to:
  /// **'Inviti in sospeso'**
  String get teamPendingInvitesSection;

  /// No description provided for @teamPendingInvitesEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun invito in sospeso.'**
  String get teamPendingInvitesEmpty;

  /// No description provided for @teamInviteFormTitle.
  ///
  /// In it, this message translates to:
  /// **'Invita un membro'**
  String get teamInviteFormTitle;

  /// No description provided for @teamInviteEmailLabel.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get teamInviteEmailLabel;

  /// No description provided for @teamRoleLabel.
  ///
  /// In it, this message translates to:
  /// **'Ruolo'**
  String get teamRoleLabel;

  /// No description provided for @teamInviteSubmit.
  ///
  /// In it, this message translates to:
  /// **'Crea invito'**
  String get teamInviteSubmit;

  /// No description provided for @teamInviteTokenTitle.
  ///
  /// In it, this message translates to:
  /// **'Token di invito'**
  String get teamInviteTokenTitle;

  /// No description provided for @teamInviteTokenWarning.
  ///
  /// In it, this message translates to:
  /// **'Copia subito questo token: viene mostrato una sola volta e non sarà più recuperabile.'**
  String get teamInviteTokenWarning;

  /// No description provided for @teamInviteTokenCopy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get teamInviteTokenCopy;

  /// No description provided for @teamInviteTokenCopied.
  ///
  /// In it, this message translates to:
  /// **'Token copiato negli appunti.'**
  String get teamInviteTokenCopied;

  /// No description provided for @teamInviteTokenDone.
  ///
  /// In it, this message translates to:
  /// **'Ho copiato'**
  String get teamInviteTokenDone;

  /// No description provided for @teamRevokeInviteAction.
  ///
  /// In it, this message translates to:
  /// **'Revoca'**
  String get teamRevokeInviteAction;

  /// No description provided for @teamRevokeInviteTitle.
  ///
  /// In it, this message translates to:
  /// **'Revoca invito'**
  String get teamRevokeInviteTitle;

  /// No description provided for @teamRevokeInviteMessage.
  ///
  /// In it, this message translates to:
  /// **'Vuoi revocare l\'invito per {email}?'**
  String teamRevokeInviteMessage(String email);

  /// No description provided for @teamRevokeInviteConfirm.
  ///
  /// In it, this message translates to:
  /// **'Revoca'**
  String get teamRevokeInviteConfirm;

  /// No description provided for @teamChangeRoleAction.
  ///
  /// In it, this message translates to:
  /// **'Cambia ruolo'**
  String get teamChangeRoleAction;

  /// No description provided for @teamChangeRoleTitle.
  ///
  /// In it, this message translates to:
  /// **'Cambia ruolo'**
  String get teamChangeRoleTitle;

  /// No description provided for @teamChangeRoleConfirm.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get teamChangeRoleConfirm;

  /// No description provided for @teamRemoveMemberAction.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get teamRemoveMemberAction;

  /// No description provided for @teamRemoveMemberTitle.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi membro'**
  String get teamRemoveMemberTitle;

  /// No description provided for @teamRemoveMemberMessage.
  ///
  /// In it, this message translates to:
  /// **'Vuoi rimuovere {name} dall\'azienda?'**
  String teamRemoveMemberMessage(String name);

  /// No description provided for @teamRemoveMemberConfirm.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get teamRemoveMemberConfirm;

  /// No description provided for @teamInviteStatusPending.
  ///
  /// In it, this message translates to:
  /// **'In sospeso'**
  String get teamInviteStatusPending;

  /// No description provided for @teamInviteStatusAccepted.
  ///
  /// In it, this message translates to:
  /// **'Accettato'**
  String get teamInviteStatusAccepted;

  /// No description provided for @teamInviteStatusRevoked.
  ///
  /// In it, this message translates to:
  /// **'Revocato'**
  String get teamInviteStatusRevoked;

  /// No description provided for @teamInviteStatusExpired.
  ///
  /// In it, this message translates to:
  /// **'Scaduto'**
  String get teamInviteStatusExpired;

  /// No description provided for @acceptInviteTitle.
  ///
  /// In it, this message translates to:
  /// **'Accetta invito'**
  String get acceptInviteTitle;

  /// No description provided for @acceptInviteSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Incolla il token ricevuto per unirti all\'azienda.'**
  String get acceptInviteSubtitle;

  /// No description provided for @acceptInviteTokenLabel.
  ///
  /// In it, this message translates to:
  /// **'Token di invito'**
  String get acceptInviteTokenLabel;

  /// No description provided for @acceptInviteTokenRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il token di invito'**
  String get acceptInviteTokenRequired;

  /// No description provided for @acceptInviteSubmit.
  ///
  /// In it, this message translates to:
  /// **'Accetta invito'**
  String get acceptInviteSubmit;

  /// No description provided for @acceptInviteSuccess.
  ///
  /// In it, this message translates to:
  /// **'Invito accettato. Ora fai parte dell\'azienda.'**
  String get acceptInviteSuccess;

  /// No description provided for @categoriesNoActiveCompany.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda attiva. Seleziona un\'azienda per continuare.'**
  String get categoriesNoActiveCompany;

  /// No description provided for @categoriesReadOnlyMessage.
  ///
  /// In it, this message translates to:
  /// **'Puoi visualizzare le categorie, ma non modificarle.'**
  String get categoriesReadOnlyMessage;

  /// No description provided for @categoriesEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessuna categoria ancora. Aggiungi la prima categoria operativa.'**
  String get categoriesEmpty;

  /// No description provided for @categoriesSectionEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessuna categoria in questa sezione.'**
  String get categoriesSectionEmpty;

  /// No description provided for @categoriesLoadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento categorie non riuscito. Riprova.'**
  String get categoriesLoadError;

  /// No description provided for @categoriesRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get categoriesRetry;

  /// No description provided for @categoriesNewButton.
  ///
  /// In it, this message translates to:
  /// **'Nuova categoria'**
  String get categoriesNewButton;

  /// No description provided for @categoriesCreateTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuova categoria'**
  String get categoriesCreateTitle;

  /// No description provided for @categoriesRenameTitle.
  ///
  /// In it, this message translates to:
  /// **'Rinomina categoria'**
  String get categoriesRenameTitle;

  /// No description provided for @categoriesNameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome'**
  String get categoriesNameLabel;

  /// No description provided for @categoriesNameRequired.
  ///
  /// In it, this message translates to:
  /// **'Il nome della categoria è obbligatorio.'**
  String get categoriesNameRequired;

  /// No description provided for @categoriesNameTooLong.
  ///
  /// In it, this message translates to:
  /// **'Il nome della categoria non può superare i 80 caratteri.'**
  String get categoriesNameTooLong;

  /// No description provided for @categoriesCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get categoriesCancel;

  /// No description provided for @categoriesSave.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get categoriesSave;

  /// No description provided for @categoriesIncomeSection.
  ///
  /// In it, this message translates to:
  /// **'Entrate'**
  String get categoriesIncomeSection;

  /// No description provided for @categoriesExpenseSection.
  ///
  /// In it, this message translates to:
  /// **'Uscite'**
  String get categoriesExpenseSection;

  /// No description provided for @categoriesActiveGroup.
  ///
  /// In it, this message translates to:
  /// **'Attive'**
  String get categoriesActiveGroup;

  /// No description provided for @categoriesArchivedGroup.
  ///
  /// In it, this message translates to:
  /// **'Archiviate'**
  String get categoriesArchivedGroup;

  /// No description provided for @categoriesArchivedBadge.
  ///
  /// In it, this message translates to:
  /// **'Archiviata'**
  String get categoriesArchivedBadge;

  /// No description provided for @categoriesRenameAction.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get categoriesRenameAction;

  /// No description provided for @categoriesArchiveAction.
  ///
  /// In it, this message translates to:
  /// **'Archivia'**
  String get categoriesArchiveAction;

  /// No description provided for @categoriesReactivateAction.
  ///
  /// In it, this message translates to:
  /// **'Riattiva'**
  String get categoriesReactivateAction;

  /// No description provided for @categoriesCreateSuccess.
  ///
  /// In it, this message translates to:
  /// **'Categoria creata.'**
  String get categoriesCreateSuccess;

  /// No description provided for @categoriesRenameSuccess.
  ///
  /// In it, this message translates to:
  /// **'Categoria rinominata.'**
  String get categoriesRenameSuccess;

  /// No description provided for @categoriesArchiveSuccess.
  ///
  /// In it, this message translates to:
  /// **'Categoria archiviata.'**
  String get categoriesArchiveSuccess;

  /// No description provided for @categoriesReactivateSuccess.
  ///
  /// In it, this message translates to:
  /// **'Categoria riattivata.'**
  String get categoriesReactivateSuccess;

  /// No description provided for @emailRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci l\'email'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un\'email valida'**
  String get emailInvalid;

  /// No description provided for @passwordRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la password'**
  String get passwordRequired;

  /// No description provided for @passwordTooShort.
  ///
  /// In it, this message translates to:
  /// **'La password deve avere almeno 8 caratteri'**
  String get passwordTooShort;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In it, this message translates to:
  /// **'Conferma password'**
  String get confirmPasswordLabel;

  /// No description provided for @confirmPasswordRequired.
  ///
  /// In it, this message translates to:
  /// **'Conferma la password'**
  String get confirmPasswordRequired;

  /// No description provided for @confirmPasswordMismatch.
  ///
  /// In it, this message translates to:
  /// **'Le password non coincidono'**
  String get confirmPasswordMismatch;

  /// No description provided for @checkEmailTitle.
  ///
  /// In it, this message translates to:
  /// **'Controlla la tua email'**
  String get checkEmailTitle;

  /// No description provided for @checkEmailSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Ti abbiamo inviato un link per confermare l\'account'**
  String get checkEmailSubtitle;

  /// No description provided for @checkEmailBackToLogin.
  ///
  /// In it, this message translates to:
  /// **'Torna al login'**
  String get checkEmailBackToLogin;

  /// No description provided for @onboardingCompanyTitle.
  ///
  /// In it, this message translates to:
  /// **'Configura la tua azienda'**
  String get onboardingCompanyTitle;

  /// No description provided for @onboardingCompanySubtitle.
  ///
  /// In it, this message translates to:
  /// **'Crea la prima azienda per iniziare a usare Project Atlas'**
  String get onboardingCompanySubtitle;

  /// No description provided for @companyNameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome azienda'**
  String get companyNameLabel;

  /// No description provided for @companyNameRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il nome dell\'azienda'**
  String get companyNameRequired;

  /// No description provided for @companySlugLabel.
  ///
  /// In it, this message translates to:
  /// **'Slug'**
  String get companySlugLabel;

  /// No description provided for @companySlugHelper.
  ///
  /// In it, this message translates to:
  /// **'Identificativo univoco dell\'azienda nell\'URL'**
  String get companySlugHelper;

  /// No description provided for @companySlugRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci lo slug'**
  String get companySlugRequired;

  /// No description provided for @companySlugInvalid.
  ///
  /// In it, this message translates to:
  /// **'Formato slug non valido. Usa solo lettere minuscole, numeri e trattini'**
  String get companySlugInvalid;

  /// No description provided for @createCompanyButton.
  ///
  /// In it, this message translates to:
  /// **'Crea azienda'**
  String get createCompanyButton;

  /// No description provided for @companiesLoadRetryButton.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get companiesLoadRetryButton;

  /// No description provided for @companySelectorTitle.
  ///
  /// In it, this message translates to:
  /// **'Seleziona azienda'**
  String get companySelectorTitle;

  /// No description provided for @companySelectorSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Scegli l\'azienda con cui vuoi lavorare'**
  String get companySelectorSubtitle;

  /// No description provided for @companySelectorEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessuna azienda disponibile'**
  String get companySelectorEmpty;

  /// No description provided for @dashboardActiveRole.
  ///
  /// In it, this message translates to:
  /// **'Ruolo: {roleLabel}'**
  String dashboardActiveRole(String roleLabel);

  /// No description provided for @dashboardCompanyWelcome.
  ///
  /// In it, this message translates to:
  /// **'Azienda: {companyName}'**
  String dashboardCompanyWelcome(String companyName);

  /// No description provided for @dashboardCompanySlug.
  ///
  /// In it, this message translates to:
  /// **'Slug: {slug}'**
  String dashboardCompanySlug(String slug);

  /// No description provided for @genericError.
  ///
  /// In it, this message translates to:
  /// **'Si è verificato un errore. Riprova.'**
  String get genericError;

  /// No description provided for @resetPasswordSuccessMessage.
  ///
  /// In it, this message translates to:
  /// **'Se l\'email è registrata, riceverai un link per reimpostare la password.'**
  String get resetPasswordSuccessMessage;

  /// No description provided for @updatePasswordTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuova password'**
  String get updatePasswordTitle;

  /// No description provided for @updatePasswordSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Scegli una nuova password per il tuo account'**
  String get updatePasswordSubtitle;

  /// No description provided for @updatePasswordButton.
  ///
  /// In it, this message translates to:
  /// **'Aggiorna password'**
  String get updatePasswordButton;

  /// No description provided for @updatePasswordSuccessMessage.
  ///
  /// In it, this message translates to:
  /// **'Password aggiornata. Accedi con le nuove credenziali.'**
  String get updatePasswordSuccessMessage;

  /// No description provided for @subscriptionPlanSectionTitle.
  ///
  /// In it, this message translates to:
  /// **'Piano e utilizzo'**
  String get subscriptionPlanSectionTitle;

  /// No description provided for @subscriptionPlanFree.
  ///
  /// In it, this message translates to:
  /// **'Piano Free'**
  String get subscriptionPlanFree;

  /// No description provided for @subscriptionPlanPremium.
  ///
  /// In it, this message translates to:
  /// **'Piano Premium'**
  String get subscriptionPlanPremium;

  /// No description provided for @subscriptionPlanTrialPremium.
  ///
  /// In it, this message translates to:
  /// **'Prova Premium'**
  String get subscriptionPlanTrialPremium;

  /// No description provided for @subscriptionDocumentsMonthlyLimit.
  ///
  /// In it, this message translates to:
  /// **'{count} documenti al mese'**
  String subscriptionDocumentsMonthlyLimit(int count);

  /// No description provided for @subscriptionDocumentsUnlimited.
  ///
  /// In it, this message translates to:
  /// **'Documenti illimitati'**
  String get subscriptionDocumentsUnlimited;

  /// No description provided for @subscriptionDocumentsUsedThisMonth.
  ///
  /// In it, this message translates to:
  /// **'{documentsUsed} di {documentMonthlyLimit} documenti utilizzati questo mese'**
  String subscriptionDocumentsUsedThisMonth(
    int documentsUsed,
    int documentMonthlyLimit,
  );

  /// No description provided for @subscriptionDocumentsUsedInfo.
  ///
  /// In it, this message translates to:
  /// **'{documentsUsed} documenti caricati questo mese'**
  String subscriptionDocumentsUsedInfo(int documentsUsed);

  /// No description provided for @subscriptionQuotaExhausted.
  ///
  /// In it, this message translates to:
  /// **'Quota mensile esaurita'**
  String get subscriptionQuotaExhausted;

  /// No description provided for @subscriptionTrialActiveLabel.
  ///
  /// In it, this message translates to:
  /// **'Prova Premium attiva'**
  String get subscriptionTrialActiveLabel;

  /// No description provided for @subscriptionStatusLabel.
  ///
  /// In it, this message translates to:
  /// **'Stato: {status}'**
  String subscriptionStatusLabel(String status);

  /// No description provided for @subscriptionStatusFree.
  ///
  /// In it, this message translates to:
  /// **'Free'**
  String get subscriptionStatusFree;

  /// No description provided for @subscriptionStatusTrialing.
  ///
  /// In it, this message translates to:
  /// **'Prova in corso'**
  String get subscriptionStatusTrialing;

  /// No description provided for @subscriptionStatusActive.
  ///
  /// In it, this message translates to:
  /// **'Attivo'**
  String get subscriptionStatusActive;

  /// No description provided for @subscriptionStatusUnknown.
  ///
  /// In it, this message translates to:
  /// **'Sconosciuto'**
  String get subscriptionStatusUnknown;

  /// No description provided for @subscriptionTrialValidUntil.
  ///
  /// In it, this message translates to:
  /// **'Prova valida fino al {trialEndDate}'**
  String subscriptionTrialValidUntil(String trialEndDate);

  /// No description provided for @subscriptionActivateTrialCta.
  ///
  /// In it, this message translates to:
  /// **'Attiva la prova Premium'**
  String get subscriptionActivateTrialCta;

  /// No description provided for @subscriptionActivateTrialDialogTitle.
  ///
  /// In it, this message translates to:
  /// **'Attivare la prova Premium?'**
  String get subscriptionActivateTrialDialogTitle;

  /// No description provided for @subscriptionActivateTrialDialogBody.
  ///
  /// In it, this message translates to:
  /// **'La prova dura un mese e può essere attivata una sola volta per questa azienda.'**
  String get subscriptionActivateTrialDialogBody;

  /// No description provided for @subscriptionActivateTrialCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get subscriptionActivateTrialCancel;

  /// No description provided for @subscriptionActivateTrialConfirm.
  ///
  /// In it, this message translates to:
  /// **'Attiva prova'**
  String get subscriptionActivateTrialConfirm;

  /// No description provided for @subscriptionTrialActivatedSuccess.
  ///
  /// In it, this message translates to:
  /// **'Prova Premium attivata.'**
  String get subscriptionTrialActivatedSuccess;

  /// No description provided for @atlasDocumentQuotaExceeded.
  ///
  /// In it, this message translates to:
  /// **'Hai raggiunto il limite di documenti del mese.'**
  String get atlasDocumentQuotaExceeded;

  /// No description provided for @atlasSubscriptionNotFound.
  ///
  /// In it, this message translates to:
  /// **'Non è stato possibile trovare l\'abbonamento dell\'azienda.'**
  String get atlasSubscriptionNotFound;

  /// No description provided for @atlasPlanNotFound.
  ///
  /// In it, this message translates to:
  /// **'Il piano associato all\'azienda non è disponibile.'**
  String get atlasPlanNotFound;

  /// No description provided for @atlasCompanyIdRequired.
  ///
  /// In it, this message translates to:
  /// **'Non è stata selezionata un\'azienda valida.'**
  String get atlasCompanyIdRequired;

  /// No description provided for @atlasNotAuthenticated.
  ///
  /// In it, this message translates to:
  /// **'La sessione non è valida. Accedi nuovamente.'**
  String get atlasNotAuthenticated;

  /// No description provided for @atlasNotCompanyMember.
  ///
  /// In it, this message translates to:
  /// **'Non fai parte di questa azienda.'**
  String get atlasNotCompanyMember;

  /// No description provided for @atlasNotCompanyOwner.
  ///
  /// In it, this message translates to:
  /// **'Solo il proprietario può attivare la prova Premium.'**
  String get atlasNotCompanyOwner;

  /// No description provided for @atlasTrialAlreadyActive.
  ///
  /// In it, this message translates to:
  /// **'La prova Premium è già attiva.'**
  String get atlasTrialAlreadyActive;

  /// No description provided for @atlasAlreadyPremium.
  ///
  /// In it, this message translates to:
  /// **'L\'azienda utilizza già il piano Premium.'**
  String get atlasAlreadyPremium;

  /// No description provided for @atlasTrialAlreadyUsed.
  ///
  /// In it, this message translates to:
  /// **'La prova Premium è già stata utilizzata.'**
  String get atlasTrialAlreadyUsed;

  /// No description provided for @atlasPremiumUnavailable.
  ///
  /// In it, this message translates to:
  /// **'La prova Premium non è disponibile in questo momento.'**
  String get atlasPremiumUnavailable;

  /// No description provided for @atlasBillingLinked.
  ///
  /// In it, this message translates to:
  /// **'La prova Premium non è disponibile perché risulta un collegamento di fatturazione per questa azienda.'**
  String get atlasBillingLinked;

  /// No description provided for @atlasBillingSyncPending.
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione fatturazione in corso. Riprova tra poco.'**
  String get atlasBillingSyncPending;

  /// No description provided for @subscriptionPlanManagementComingSoon.
  ///
  /// In it, this message translates to:
  /// **'La gestione del piano sarà disponibile prossimamente.'**
  String get subscriptionPlanManagementComingSoon;

  /// No description provided for @subscriptionLoading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento piano...'**
  String get subscriptionLoading;

  /// No description provided for @subscriptionLoadError.
  ///
  /// In it, this message translates to:
  /// **'Caricamento piano non riuscito. Riprova.'**
  String get subscriptionLoadError;

  /// No description provided for @subscriptionUpgradeToPremiumCta.
  ///
  /// In it, this message translates to:
  /// **'Passa a Premium'**
  String get subscriptionUpgradeToPremiumCta;

  /// No description provided for @subscriptionCheckoutPreparing.
  ///
  /// In it, this message translates to:
  /// **'Preparazione del checkout...'**
  String get subscriptionCheckoutPreparing;

  /// No description provided for @atlasCheckoutStartFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile avviare il checkout.'**
  String get atlasCheckoutStartFailed;

  /// No description provided for @atlasCheckoutUnavailable.
  ///
  /// In it, this message translates to:
  /// **'Checkout temporaneamente non disponibile.'**
  String get atlasCheckoutUnavailable;

  /// No description provided for @atlasCheckoutNotEligible.
  ///
  /// In it, this message translates to:
  /// **'Non puoi avviare il checkout per questa azienda.'**
  String get atlasCheckoutNotEligible;

  /// No description provided for @atlasCheckoutAlreadyOpen.
  ///
  /// In it, this message translates to:
  /// **'Esiste già un checkout aperto.'**
  String get atlasCheckoutAlreadyOpen;

  /// No description provided for @atlasCheckoutInProgress.
  ///
  /// In it, this message translates to:
  /// **'Checkout già in preparazione. Attendi qualche secondo.'**
  String get atlasCheckoutInProgress;

  /// No description provided for @atlasProviderOutcomeUnknown.
  ///
  /// In it, this message translates to:
  /// **'Stato del pagamento non ancora confermato.'**
  String get atlasProviderOutcomeUnknown;

  /// No description provided for @atlasCheckoutOpenFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire la pagina di pagamento.'**
  String get atlasCheckoutOpenFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
