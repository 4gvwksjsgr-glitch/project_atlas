import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/clients/data/models/customer_model.dart';

void main() {
  group('CustomerModel', () {
    test('mappa JSON in Customer entity', () {
      final model = CustomerModel.fromJson({
        'id': 'c1',
        'company_id': 'co1',
        'name': 'Rossi',
        'email': 'rossi@example.com',
        'phone': null,
        'notes': 'VIP',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-02T00:00:00.000Z',
      });

      final entity = model.toEntity();
      expect(entity.id, 'c1');
      expect(entity.companyId, 'co1');
      expect(entity.name, 'Rossi');
      expect(entity.email, 'rossi@example.com');
      expect(entity.phone, isNull);
      expect(entity.notes, 'VIP');
    });
  });
}
