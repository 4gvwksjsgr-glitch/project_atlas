import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Variabili d'ambiente caricate da `.env` tramite [flutter_dotenv].
abstract final class Env {
  static String get supabaseUrl => _require('SUPABASE_URL');

  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

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
}
