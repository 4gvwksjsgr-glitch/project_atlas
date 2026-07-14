import '../../../../core/utils/result.dart';
import '../entities/company.dart';
import '../repositories/company_repository.dart';

class CreateCompany {
  const CreateCompany(this._repository);

  final CompanyRepository _repository;

  Future<Result<Company>> call({required String name, required String slug}) {
    return _repository.createCompany(
      name: name.trim(),
      slug: slug.trim().toLowerCase(),
    );
  }
}
