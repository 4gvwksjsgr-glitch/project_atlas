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
  String get logoutButton => 'Esci';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navClients => 'Clienti';

  @override
  String get navTransactions => 'Movimenti';

  @override
  String get navSettings => 'Impostazioni';

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
