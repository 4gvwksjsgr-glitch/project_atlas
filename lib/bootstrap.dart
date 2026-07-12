import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/config/env.dart';
import 'core/logging/app_logger.dart';
import 'core/network/supabase_client.dart';

/// Inizializza servizi globali prima dell'avvio dell'app.
Future<void> bootstrap() async {
  await dotenv.load(fileName: '.env');

  AppLogger.instance.initialize(
    minLevel: LogLevel.fromString(Env.logLevel),
  );

  AppLogger.instance.info(
    'Avvio Project Atlas',
    context: {'env': Env.appEnv},
  );

  await initializeSupabase();
}
