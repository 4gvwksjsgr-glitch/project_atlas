import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/utils/result.dart';

void main() {
  group('Result', () {
    test('Success holds value', () {
      const result = Success<int>(42);

      expect(result.isSuccess, isTrue);
      expect(result.isError, isFalse);
      expect(result.when(success: (value) => value, error: (_) => -1), 42);
    });

    test('Error holds failure', () {
      const result = Error<int>(ValidationFailure('Campo obbligatorio'));

      expect(result.isSuccess, isFalse);
      expect(result.isError, isTrue);
      expect(
        result.when(success: (_) => 'ok', error: (failure) => failure.message),
        'Campo obbligatorio',
      );
    });
  });
}
