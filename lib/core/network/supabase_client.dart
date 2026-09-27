import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../logging/app_logger.dart';

/// Inizializza e espone il client Supabase.
Future<SupabaseClient> initializeSupabase() async {
  AppLogger.instance.info('Inizializzazione Supabase');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      // Web: keep detectSessionInUri=false — explicit PKCE in bootstrap.
      // Native: let supabase_flutter observe projectatlas://auth/callback.
      detectSessionInUri: !kIsWeb,
    ),
  );

  return Supabase.instance.client;
}

SupabaseClient get supabaseClient => Supabase.instance.client;
