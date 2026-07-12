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
  String get genericError => 'Si è verificato un errore. Riprova.';
}
