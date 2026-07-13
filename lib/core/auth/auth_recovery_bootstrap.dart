/// Stato bootstrap per la sessione di recovery password.
///
/// Usato tra [bootstrap] e i provider Riverpod, prima del primo frame.
abstract final class AuthRecoveryBootstrap {
  static bool _pendingRecovery = false;
  static String? _authLinkError;

  static void activateRecovery() {
    _pendingRecovery = true;
  }

  static bool consumePendingRecovery() {
    if (!_pendingRecovery) {
      return false;
    }
    _pendingRecovery = false;
    return true;
  }

  static void setLinkError(String message) {
    _authLinkError = message;
  }

  static String? consumeLinkError() {
    final message = _authLinkError;
    _authLinkError = null;
    return message;
  }
}
