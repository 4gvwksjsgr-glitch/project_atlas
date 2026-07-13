import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../logging/app_logger.dart';

/// Inizializza e espone il client Supabase.
Future<SupabaseClient> initializeSupabase() async {
  AppLogger.instance.info('Inizializzazione Supabase');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // Gestione esplicita del callback PKCE in bootstrap (hash routing).
      detectSessionInUri: false,
    ),
  );

  return Supabase.instance.client;
}

SupabaseClient get supabaseClient => Supabase.instance.client;
