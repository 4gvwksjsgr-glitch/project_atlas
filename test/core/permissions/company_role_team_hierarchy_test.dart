import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';

void main() {
  group('CompanyRole team hierarchy', () {
    test('admin cannot manage owner or admin targets', () {
      expect(
        CompanyRole.admin.canManageMemberTarget(CompanyRole.owner),
        isFalse,
      );
      expect(
        CompanyRole.admin.canManageMemberTarget(CompanyRole.admin),
        isFalse,
      );
      expect(
        CompanyRole.admin.canManageMemberTarget(CompanyRole.manager),
        isTrue,
      );
      expect(
        CompanyRole.admin.canManageMemberTarget(CompanyRole.employee),
        isTrue,
      );
    });

    test('admin assignable roles are manager and employee only', () {
      expect(
        CompanyRole.admin.assignableMemberRoles,
        [CompanyRole.manager, CompanyRole.employee],
      );
      expect(
        CompanyRole.admin.assignableMemberRoles,
        isNot(contains(CompanyRole.admin)),
      );
      expect(
        CompanyRole.admin.assignableMemberRoles,
        isNot(contains(CompanyRole.owner)),
      );
    });

    test('owner retains management of all roles and full assignable set', () {
      for (final target in CompanyRole.values) {
        expect(
          CompanyRole.owner.canManageMemberTarget(target),
          isTrue,
          reason: 'owner should manage $target',
        );
      }
      expect(
        CompanyRole.owner.assignableMemberRoles,
        CompanyRole.values,
      );
    });

    test('manager and employee have no team-management privilege', () {
      expect(CompanyRole.manager.canManageMembers, isFalse);
      expect(CompanyRole.employee.canManageMembers, isFalse);
      expect(
        CompanyRole.manager.canManageMemberTarget(CompanyRole.employee),
        isFalse,
      );
      expect(CompanyRole.employee.assignableMemberRoles, isEmpty);
    });
  });
}
