/// Stato esplicito delle membership aziendali per i redirect auth.
sealed class UserCompaniesRouteState {
  const UserCompaniesRouteState();
}

final class UserCompaniesLoading extends UserCompaniesRouteState {
  const UserCompaniesLoading();
}

final class UserCompaniesEmpty extends UserCompaniesRouteState {
  const UserCompaniesEmpty();
}

final class UserCompaniesNeedsSelection extends UserCompaniesRouteState {
  const UserCompaniesNeedsSelection();
}

final class UserCompaniesReady extends UserCompaniesRouteState {
  const UserCompaniesReady();
}

final class UserCompaniesError extends UserCompaniesRouteState {
  const UserCompaniesError(this.message);

  final String message;
}
