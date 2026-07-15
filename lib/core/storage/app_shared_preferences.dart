import 'package:shared_preferences/shared_preferences.dart';

SharedPreferences? appSharedPreferences;

Future<void> initializeAppSharedPreferences() async {
  appSharedPreferences = await SharedPreferences.getInstance();
}
