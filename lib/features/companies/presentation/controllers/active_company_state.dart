import '../../domain/entities/active_company_context.dart';

class ActiveCompanyState {
  const ActiveCompanyState({this.context, this.resolved = false});

  final ActiveCompanyContext? context;
  final bool resolved;

  ActiveCompanyState copyWith({
    ActiveCompanyContext? context,
    bool? resolved,
    bool clearContext = false,
  }) {
    return ActiveCompanyState(
      context: clearContext ? null : context ?? this.context,
      resolved: resolved ?? this.resolved,
    );
  }
}
