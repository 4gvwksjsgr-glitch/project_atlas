import 'dart:typed_data';

/// Handle multipiattaforma di un file scelto dal picker (testabile senza XFile).
abstract class PickedFileHandle {
  String get name;

  String? get mimeType;

  Future<int> length();

  Future<Uint8List> readAsBytes();
}
