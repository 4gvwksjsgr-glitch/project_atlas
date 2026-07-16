/// Ruoli di un membro all'interno di un'azienda.
enum CompanyRole {
  owner,
  admin,
  manager,
  employee;

  String get label => switch (this) {
    CompanyRole.owner => 'Proprietario',
    CompanyRole.admin => 'Amministratore',
    CompanyRole.manager => 'Manager',
    CompanyRole.employee => 'Dipendente',
  };

  /// Owner e admin possono modificare nome/slug azienda (la RLS resta il gate reale).
  bool get canEditCompanyProfile =>
      this == CompanyRole.owner || this == CompanyRole.admin;
}
