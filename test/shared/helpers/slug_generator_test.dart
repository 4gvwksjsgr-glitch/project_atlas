import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/shared/helpers/slug_generator.dart';

void main() {
  group('SlugGenerator', () {
    test('fromName normalizza spazi e caratteri speciali', () {
      expect(SlugGenerator.fromName('Acme Corp S.r.l.'), 'acme-corp-srl');
      expect(SlugGenerator.fromName('  My   Company  '), 'my-company');
    });

    test('fromName rimuove diacritici comuni', () {
      expect(SlugGenerator.fromName('Caffè Milano'), 'caffe-milano');
    });

    test('fromName restituisce stringa vuota per input non valido', () {
      expect(SlugGenerator.fromName('   '), '');
      expect(SlugGenerator.fromName('!!!'), '');
    });

    test('isValid verifica il formato slug', () {
      expect(SlugGenerator.isValid('valid-slug-123'), isTrue);
      expect(SlugGenerator.isValid('Invalid_Slug'), isFalse);
      expect(SlugGenerator.isValid('-leading'), isFalse);
    });
  });
}
