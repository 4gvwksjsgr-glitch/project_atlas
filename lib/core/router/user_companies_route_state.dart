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

final class UserCompaniesAvailable extends UserCompaniesRouteState {
  const UserCompaniesAvailable();
}

final class UserCompaniesError extends UserCompaniesRouteState {
  const UserCompaniesError(this.message);

  final String message;
}
