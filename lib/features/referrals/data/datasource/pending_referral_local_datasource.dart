import 'package:shared_preferences/shared_preferences.dart';

/// Persists a pending referral code across auth (signup / login).
class PendingReferralLocalDataSource {
  const PendingReferralLocalDataSource(this._preferences);

  final SharedPreferences _preferences;

  static const storageKey = 'atlas_pending_referral_code';

  String? getPendingCode() {
    final value = _preferences.getString(storageKey);
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> setPendingCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      await clearPendingCode();
      return;
    }
    await _preferences.setString(storageKey, trimmed);
  }

  Future<void> clearPendingCode() async {
    await _preferences.remove(storageKey);
  }
}
