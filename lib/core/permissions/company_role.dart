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

  /// Owner, admin e manager gestiscono l'anagrafica clienti (la RLS resta il gate reale).
  bool get canManageCustomers =>
      this == CompanyRole.owner ||
      this == CompanyRole.admin ||
      this == CompanyRole.manager;

  /// Owner, admin e manager gestiscono i movimenti di cassa (la RLS resta il gate reale).
  bool get canManageTransactions =>
      this == CompanyRole.owner ||
      this == CompanyRole.admin ||
      this == CompanyRole.manager;
}
