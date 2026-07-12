import '../extensions/string_extensions.dart';

/// Validatori condivisi per i form delle feature.
abstract final class Validators {
  static String? email(
    String? value, {
    required String emptyMessage,
    required String invalidMessage,
  }) {
    if (value == null || value.isBlank) {
      return emptyMessage;
    }

    final normalized = value.normalized;
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

    if (!emailRegex.hasMatch(normalized)) {
      return invalidMessage;
    }

    return null;
  }

  static String? requiredField(
    String? value, {
    required String message,
  }) {
    if (value == null || value.isBlank) {
      return message;
    }
    return null;
  }
}
