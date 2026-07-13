import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Variabili d'ambiente caricate da `.env` tramite [flutter_dotenv].
abstract final class Env {
  static String get supabaseUrl => _require('SUPABASE_URL');

  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  /// URL pubblico dell'app (es. `http://localhost:8080` per Flutter Web).
  ///
  /// Con hash routing, Supabase reindirizza qui; l'app intercetta
  /// [AuthChangeEvent.passwordRecovery] e naviga a `/auth/update-password`.
  static String get appUrl => _validateAppUrl(_require('APP_URL'));

  static String get appEnv => dotenv.env['APP_ENV'] ?? 'development';

  static String get logLevel => dotenv.env['LOG_LEVEL'] ?? 'debug';

  static bool get isProduction => appEnv == 'production';

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) {
      throw StateError(
        'Variabile d\'ambiente mancante: $key. '
        'Copia .env.example in .env e compila i valori.',
      );
    }
    return value.trim();
  }

  static String _validateAppUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw StateError(
        'APP_URL non valido: "$value". '
        'Usa un URL assoluto con schema http o https, '
        'es. http://localhost:8080',
      );
    }

    if (value.endsWith('/') && value.length > 1) {
      return value.substring(0, value.length - 1);
    }

    return value;
  }
}
