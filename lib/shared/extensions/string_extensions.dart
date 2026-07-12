/// Extension utili su [String] usate in form e validatori.
extension StringExtensions on String {
  bool get isBlank => trim().isEmpty;

  String get normalized => trim().toLowerCase();
}
