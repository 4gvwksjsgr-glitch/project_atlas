import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/auth/supabase_auth_uri_handler.dart';
import 'core/config/env.dart';
import 'core/logging/app_logger.dart';
import 'core/network/supabase_client.dart';

/// Inizializza servizi globali prima dell'avvio dell'app.
Future<void> bootstrap() async {
  final launchUri = kIsWeb ? Uri.base : Uri();
  final hadAuthCallbackAtLaunch =
      kIsWeb && SupabaseAuthUriHandler.hasAuthCallbackParams(launchUri);

  await dotenv.load(fileName: '.env');

  AppLogger.instance.initialize(minLevel: LogLevel.fromString(Env.logLevel));

  AppLogger.instance.info('Avvio Project Atlas', context: {'env': Env.appEnv});

  AppLogger.instance.debug(
    'APP_URL configurato',
    context: {'appUrl': Env.appUrl},
  );

  final client = await initializeSupabase();

  await SupabaseAuthUriHandler.completeSessionFromLaunchUri(
    client,
    launchUri: launchUri,
    hadAuthCallbackAtLaunch: hadAuthCallbackAtLaunch,
  );
}
