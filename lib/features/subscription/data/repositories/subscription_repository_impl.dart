import '../../../../core/errors/subscription_error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/company_subscription_overview.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../datasource/subscription_remote_datasource.dart';

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  SubscriptionRepositoryImpl(this._remote);

  final SubscriptionRemoteDataSource _remote;

  @override
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    try {
      final model = await _remote.getCompanySubscriptionOverview(
        companyId: companyId,
      );
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        SubscriptionErrorMapper.mapException(
          error,
          SubscriptionOperation.getOverview,
        ),
      );
    }
  }
}
