import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import '../network/supabase_client.dart';
import '../router/app_router.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return supabaseClient;
});

final appLoggerProvider = Provider<AppLogger>((ref) {
  return AppLogger.instance;
});

final goRouterProvider = routerProvider;
