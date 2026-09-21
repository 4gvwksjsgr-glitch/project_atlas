import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/company_role.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../../domain/entities/company_invite.dart';
import '../../domain/entities/company_member.dart';
import '../controllers/active_company_controller.dart';
import '../controllers/company_onboarding_controller.dart';
import '../controllers/company_team_controller.dart';

class CompanyTeamScreen extends ConsumerWidget {
  const CompanyTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.teamTitle)),
        body: Padding(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: Text(
            l10n.teamNoActiveCompany,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return CompanyTeamBody(
      key: ValueKey(activeCompany.companyId),
      companyId: activeCompany.companyId,
      actorRole: activeCompany.role,
    );
  }
}

class CompanyTeamBody extends ConsumerStatefulWidget {
  const CompanyTeamBody({
    super.key,
    required this.companyId,
    required this.actorRole,
  });

  final String companyId;
  final CompanyRole actorRole;

  @override
  ConsumerState<CompanyTeamBody> createState() => _CompanyTeamBodyState();
}

class _CompanyTeamBodyState extends ConsumerState<CompanyTeamBody> {
  final _inviteFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  CompanyRole? _selectedInviteRole;

  bool get _canManage => widget.actorRole.canManageMembers;

  List<CompanyRole> get _inviteableRoles {
    return switch (widget.actorRole) {
      CompanyRole.owner => const [
        CompanyRole.admin,
        CompanyRole.manager,
        CompanyRole.employee,
      ],
      CompanyRole.admin => const [
        CompanyRole.manager,
        CompanyRole.employee,
      ],
      _ => const <CompanyRole>[],
    };
  }

  @override
  void initState() {
    super.initState();
    final roles = _inviteableRoles;
    _selectedInviteRole = roles.isEmpty ? null : roles.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(companyTeamControllerProvider(widget.companyId).notifier).load();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handleTeamState(
    CompanyTeamControllerState? previous,
    CompanyTeamControllerState next,
  ) {
    final token = next.lastCreatedInviteToken;
    if (token != null &&
        token.isNotEmpty &&
        token != previous?.lastCreatedInviteToken) {
      _showInviteTokenDialog(token);
    }
  }

  Future<void> _showInviteTokenDialog(String token) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.teamInviteTokenTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.teamInviteTokenWarning),
              const SizedBox(height: AppUiConstants.spacingMedium),
              SelectableText(
                token,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(l10n.teamInviteTokenCopied)),
                  );
                }
              },
              child: Text(l10n.teamInviteTokenCopy),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref
                    .read(
                      companyTeamControllerProvider(widget.companyId).notifier,
                    )
                    .clearLastCreatedInviteToken();
              },
              child: Text(l10n.teamInviteTokenDone),
            ),
          ],
        );
      },
    );

    if (mounted) {
      ref
          .read(companyTeamControllerProvider(widget.companyId).notifier)
          .clearLastCreatedInviteToken();
      _emailController.clear();
    }
  }

  Future<void> _submitInvite() async {
    if (!_canManage || !(_inviteFormKey.currentState?.validate() ?? false)) {
      return;
    }
    final role = _selectedInviteRole;
    if (role == null) {
      return;
    }

    await ref
        .read(companyTeamControllerProvider(widget.companyId).notifier)
        .createInvite(email: _emailController.text, role: role);
  }

  Future<void> _confirmRevoke(CompanyInvite invite) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.teamRevokeInviteTitle),
        content: Text(l10n.teamRevokeInviteMessage(invite.emailNormalized)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.teamRevokeInviteConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(companyTeamControllerProvider(widget.companyId).notifier)
          .revokeInvite(invite.inviteId);
    }
  }

  Future<void> _changeRoleDialog(CompanyMember member) async {
    if (!_canManageTarget(member)) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final roles = _rolesAssignableTo(member);
    if (roles.isEmpty) {
      return;
    }

    CompanyRole selected = member.role;
    final confirmed = await showDialog<CompanyRole>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.teamChangeRoleTitle),
              content: DropdownButtonFormField<CompanyRole>(
                key: ValueKey(selected),
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: l10n.teamRoleLabel,
                  border: const OutlineInputBorder(),
                ),
                items: roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selected = value);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: Text(l10n.teamChangeRoleConfirm),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != null && confirmed != member.role && mounted) {
      await ref
          .read(companyTeamControllerProvider(widget.companyId).notifier)
          .changeRole(userId: member.userId, role: confirmed);
    }
  }

  bool _canManageTarget(CompanyMember member) =>
      widget.actorRole.canManageMemberTarget(member.role);

  List<CompanyRole> _rolesAssignableTo(CompanyMember member) {
    if (!_canManageTarget(member)) {
      return const [];
    }
    return widget.actorRole.assignableMemberRoles;
  }

  Future<void> _confirmRemove(CompanyMember member) async {
    if (!_canManageTarget(member)) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final label = member.fullName?.isNotEmpty == true
        ? member.fullName!
        : member.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.teamRemoveMemberTitle),
        content: Text(l10n.teamRemoveMemberMessage(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.teamRemoveMemberConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(companyTeamControllerProvider(widget.companyId).notifier)
          .removeMember(member.userId);
    }
  }

  String _inviteStatusLabel(AppLocalizations l10n, CompanyInviteStatus status) {
    return switch (status) {
      CompanyInviteStatus.pending => l10n.teamInviteStatusPending,
      CompanyInviteStatus.accepted => l10n.teamInviteStatusAccepted,
      CompanyInviteStatus.revoked => l10n.teamInviteStatusRevoked,
      CompanyInviteStatus.expired => l10n.teamInviteStatusExpired,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(companyTeamControllerProvider(widget.companyId));

    ref.listen(
      companyTeamControllerProvider(widget.companyId),
      _handleTeamState,
    );

    final pendingInvites = state.invites
        .where((i) => i.status == CompanyInviteStatus.pending)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teamTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RoutePaths.settingsCompany);
            }
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: state.isLoading && state.members.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => ref
                    .read(
                      companyTeamControllerProvider(widget.companyId).notifier,
                    )
                    .load(),
                child: ListView(
                  children: [
                    Text(
                      l10n.teamSubtitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!_canManage) ...[
                      const SizedBox(height: AppUiConstants.spacingMedium),
                      Text(
                        l10n.teamReadOnlyMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: AppUiConstants.spacingMedium),
                      Text(
                        state.errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppUiConstants.spacingLarge),
                    Text(
                      l10n.teamMembersSection,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppUiConstants.spacingSmall),
                    if (state.members.isEmpty)
                      Text(
                        l10n.teamMembersEmpty,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ...state.members.map((member) {
                        final subtitle = member.fullName?.isNotEmpty == true
                            ? '${member.email} · ${member.role.label}'
                            : member.role.label;
                        final showActions = _canManageTarget(member);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            member.fullName?.isNotEmpty == true
                                ? member.fullName!
                                : member.email,
                          ),
                          subtitle: Text(subtitle),
                          trailing: showActions
                              ? PopupMenuButton<String>(
                                  enabled: !state.isMutating,
                                  onSelected: (value) {
                                    if (value == 'role') {
                                      _changeRoleDialog(member);
                                    } else if (value == 'remove') {
                                      _confirmRemove(member);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'role',
                                      child: Text(l10n.teamChangeRoleAction),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Text(l10n.teamRemoveMemberAction),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      }),
                    if (_canManage) ...[
                      const SizedBox(height: AppUiConstants.spacingLarge),
                      Text(
                        l10n.teamPendingInvitesSection,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppUiConstants.spacingSmall),
                      if (pendingInvites.isEmpty)
                        Text(
                          l10n.teamPendingInvitesEmpty,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ...pendingInvites.map((invite) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(invite.emailNormalized),
                            subtitle: Text(
                              '${invite.role.label} · '
                              '${_inviteStatusLabel(l10n, invite.status)}',
                            ),
                            trailing: TextButton(
                              onPressed: state.isMutating
                                  ? null
                                  : () => _confirmRevoke(invite),
                              child: Text(l10n.teamRevokeInviteAction),
                            ),
                          );
                        }),
                      const SizedBox(height: AppUiConstants.spacingLarge),
                      Text(
                        l10n.teamInviteFormTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppUiConstants.spacingMedium),
                      Form(
                        key: _inviteFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              enabled: !state.isMutating,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: l10n.teamInviteEmailLabel,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) => Validators.email(
                                value,
                                emptyMessage: l10n.emailRequired,
                                invalidMessage: l10n.emailInvalid,
                              ),
                            ),
                            const SizedBox(height: AppUiConstants.spacingMedium),
                            DropdownButtonFormField<CompanyRole>(
                              key: ValueKey(_selectedInviteRole),
                              initialValue: _selectedInviteRole,
                              decoration: InputDecoration(
                                labelText: l10n.teamRoleLabel,
                                border: const OutlineInputBorder(),
                              ),
                              items: _inviteableRoles
                                  .map(
                                    (role) => DropdownMenuItem(
                                      value: role,
                                      child: Text(role.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: state.isMutating
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _selectedInviteRole = value;
                                      });
                                    },
                            ),
                            const SizedBox(height: AppUiConstants.spacingLarge),
                            FilledButton(
                              onPressed: state.isMutating ? null : _submitInvite,
                              child: state.isMutating &&
                                      state.actionStatus ==
                                          CompanyActionStatus.loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.teamInviteSubmit),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
