import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/company_role.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/company_invite.dart';
import '../../domain/entities/company_member.dart';
import 'active_company_controller.dart';
import 'company_onboarding_controller.dart';
import '../providers/company_providers.dart';

class CompanyTeamControllerState {
  const CompanyTeamControllerState({
    this.members = const [],
    this.invites = const [],
    this.isLoading = false,
    this.isMutating = false,
    this.errorMessage,
    this.lastCreatedInviteToken,
    this.actionStatus = CompanyActionStatus.idle,
  });

  final List<CompanyMember> members;
  final List<CompanyInvite> invites;
  final bool isLoading;
  final bool isMutating;
  final String? errorMessage;
  final String? lastCreatedInviteToken;
  final CompanyActionStatus actionStatus;

  CompanyTeamControllerState copyWith({
    List<CompanyMember>? members,
    List<CompanyInvite>? invites,
    bool? isLoading,
    bool? isMutating,
    String? errorMessage,
    String? lastCreatedInviteToken,
    CompanyActionStatus? actionStatus,
    bool clearError = false,
    bool clearToken = false,
  }) {
    return CompanyTeamControllerState(
      members: members ?? this.members,
      invites: invites ?? this.invites,
      isLoading: isLoading ?? this.isLoading,
      isMutating: isMutating ?? this.isMutating,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastCreatedInviteToken: clearToken
          ? null
          : lastCreatedInviteToken ?? this.lastCreatedInviteToken,
      actionStatus: actionStatus ?? this.actionStatus,
    );
  }
}

class CompanyTeamController
    extends AutoDisposeFamilyNotifier<CompanyTeamControllerState, String> {
  @override
  CompanyTeamControllerState build(String companyId) {
    return const CompanyTeamControllerState();
  }

  Future<void> load() async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      actionStatus: CompanyActionStatus.loading,
    );

    final membersResult = await ref
        .read(listCompanyMembersUseCaseProvider)
        .call(arg);

    late final List<CompanyMember> members;
    switch (membersResult) {
      case Error(:final failure):
        state = state.copyWith(
          isLoading: false,
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return;
      case Success(:final value):
        members = value;
    }

    final active = ref.read(activeCompanyProvider);
    final canManage = active?.role.canManageMembers ?? false;
    List<CompanyInvite> invites = const [];

    if (canManage) {
      final invitesResult = await ref
          .read(listCompanyInvitesUseCaseProvider)
          .call(arg);

      switch (invitesResult) {
        case Error(:final failure):
          state = state.copyWith(
            isLoading: false,
            members: members,
            actionStatus: CompanyActionStatus.error,
            errorMessage: failure.message,
          );
          return;
        case Success(:final value):
          invites = value;
      }
    }

    state = state.copyWith(
      isLoading: false,
      members: members,
      invites: invites,
      actionStatus: CompanyActionStatus.success,
      clearError: true,
    );
  }

  Future<void> createInvite({
    required String email,
    required CompanyRole role,
    int? expiresInHours,
  }) async {
    if (state.isMutating) {
      return;
    }

    state = state.copyWith(
      isMutating: true,
      clearError: true,
      clearToken: true,
      actionStatus: CompanyActionStatus.loading,
    );

    final result = await ref
        .read(createCompanyInviteUseCaseProvider)
        .call(
          companyId: arg,
          email: email,
          role: role,
          expiresInHours: expiresInHours,
        );

    switch (result) {
      case Success(:final value):
        state = state.copyWith(
          isMutating: false,
          lastCreatedInviteToken: value.inviteToken,
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        await load();
      case Error(:final failure):
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
          clearToken: true,
        );
    }
  }

  Future<void> revokeInvite(String inviteId) async {
    if (state.isMutating) {
      return;
    }

    state = state.copyWith(
      isMutating: true,
      clearError: true,
      actionStatus: CompanyActionStatus.loading,
    );

    final result = await ref
        .read(revokeCompanyInviteUseCaseProvider)
        .call(inviteId);

    switch (result) {
      case Success():
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        await load();
      case Error(:final failure):
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> changeRole({
    required String userId,
    required CompanyRole role,
  }) async {
    if (state.isMutating) {
      return;
    }

    state = state.copyWith(
      isMutating: true,
      clearError: true,
      actionStatus: CompanyActionStatus.loading,
    );

    final result = await ref
        .read(changeCompanyMemberRoleUseCaseProvider)
        .call(companyId: arg, userId: userId, role: role);

    switch (result) {
      case Success():
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        await load();
      case Error(:final failure):
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> removeMember(String userId) async {
    if (state.isMutating) {
      return;
    }

    state = state.copyWith(
      isMutating: true,
      clearError: true,
      actionStatus: CompanyActionStatus.loading,
    );

    final result = await ref
        .read(removeCompanyMemberUseCaseProvider)
        .call(companyId: arg, userId: userId);

    switch (result) {
      case Success():
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        await load();
      case Error(:final failure):
        state = state.copyWith(
          isMutating: false,
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
    }
  }

  void clearLastCreatedInviteToken() {
    state = state.copyWith(clearToken: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final companyTeamControllerProvider = NotifierProvider.autoDispose
    .family<CompanyTeamController, CompanyTeamControllerState, String>(
      CompanyTeamController.new,
    );
