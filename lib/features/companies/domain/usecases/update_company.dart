import '../../../../core/utils/result.dart';
import '../entities/company.dart';
import '../repositories/company_repository.dart';

class UpdateCompany {
  const UpdateCompany(this._repository);

  final CompanyRepository _repository;

  Future<Result<Company>> call({
    required String companyId,
    required String name,
    required String slug,
  }) {
    return _repository.updateCompany(
      companyId: companyId,
      name: name.trim(),
      slug: slug.trim().toLowerCase(),
    );
  }
}
