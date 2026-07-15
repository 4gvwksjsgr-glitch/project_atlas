import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> setUpMockSharedPreferences([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  appSharedPreferences = await SharedPreferences.getInstance();
}
