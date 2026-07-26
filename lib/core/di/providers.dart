import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../files/app_file_picker.dart';
import '../files/file_selector_app_file_picker.dart';
import '../logging/app_logger.dart';
import '../network/supabase_client.dart';
import '../router/app_router.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return supabaseClient;
});

final appLoggerProvider = Provider<AppLogger>((ref) {
  return AppLogger.instance;
});

final appFilePickerProvider = Provider<AppFilePicker>((ref) {
  return FileSelectorAppFilePicker();
});

final goRouterProvider = routerProvider;
