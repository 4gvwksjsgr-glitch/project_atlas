import 'package:shared_preferences/shared_preferences.dart';

class ActiveCompanyLocalDataSource {
  const ActiveCompanyLocalDataSource(this._preferences);

  final SharedPreferences _preferences;

  static String storageKeyForUser(String userId) => 'active_company_id_$userId';

  String? getPersistedCompanyId(String userId) {
    return _preferences.getString(storageKeyForUser(userId));
  }

  Future<void> persistActiveCompanyId({
    required String userId,
    required String companyId,
  }) async {
    await _preferences.setString(storageKeyForUser(userId), companyId);
  }

  Future<void> clearPersistedCompanyId(String userId) async {
    await _preferences.remove(storageKeyForUser(userId));
  }
}
