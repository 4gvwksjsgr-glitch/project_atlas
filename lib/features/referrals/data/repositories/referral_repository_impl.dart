import '../../../../core/errors/referral_error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/referral_link.dart';
import '../../domain/entities/referral_overview.dart';
import '../../domain/repositories/referral_repository.dart';
import '../datasource/referral_remote_datasource.dart';

class ReferralRepositoryImpl implements ReferralRepository {
  ReferralRepositoryImpl(this._remote);

  final ReferralRemoteDataSource _remote;

  @override
  Future<Result<ReferralLink>> getOrCreateCompanyReferralLink({
    required String companyId,
  }) async {
    try {
      final model = await _remote.getOrCreateCompanyReferralLink(
        companyId: companyId,
      );
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        ReferralErrorMapper.mapException(
          error,
          ReferralOperation.getOrCreateLink,
        ),
      );
    }
  }

  @override
  Future<Result<ReferralLink>> regenerateCompanyReferralLink({
    required String companyId,
  }) async {
    try {
      final model = await _remote.regenerateCompanyReferralLink(
        companyId: companyId,
      );
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        ReferralErrorMapper.mapException(
          error,
          ReferralOperation.regenerateLink,
        ),
      );
    }
  }

  @override
  Future<Result<ClaimReferralResult>> claimReferral({
    required String code,
  }) async {
    try {
      final model = await _remote.claimReferral(code: code);
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        ReferralErrorMapper.mapException(error, ReferralOperation.claim),
      );
    }
  }

  @override
  Future<Result<ReferralOverview>> getReferralOverview({
    required String companyId,
  }) async {
    try {
      final model = await _remote.getReferralOverview(companyId: companyId);
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        ReferralErrorMapper.mapException(
          error,
          ReferralOperation.getOverview,
        ),
      );
    }
  }

  @override
  Future<Result<RetryReferralRedemptionResult>> retryReferralRedemption({
    required String companyId,
  }) async {
    try {
      final model = await _remote.retryReferralRedemption(
        companyId: companyId,
      );
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        ReferralErrorMapper.mapException(
          error,
          ReferralOperation.retryRedemption,
        ),
      );
    }
  }
}
