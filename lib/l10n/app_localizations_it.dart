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
  String get dashboardPlaceholder =>
      'Le statistiche saranno disponibili nelle prossime fasi';

  @override
  String get logoutButton => 'Esci';

  @override
  String get navDashboard => 'Dashboard';

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
  String dashboardCompanyWelcome(String companyName) {
    return 'Azienda: $companyName';
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
