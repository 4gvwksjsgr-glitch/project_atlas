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

  /// Owner e admin gestiscono invitati e membri (la RLS resta il gate reale).
  bool get canManageMembers =>
      this == CompanyRole.owner || this == CompanyRole.admin;

  /// Whether this actor may change/remove [target] (server remains authoritative).
  /// Admin may only manage manager/employee; owner/admin targets are owner-only.
  bool canManageMemberTarget(CompanyRole target) {
    if (!canManageMembers) return false;
    if (this == CompanyRole.owner) return true;
    return target == CompanyRole.manager || target == CompanyRole.employee;
  }

  /// Roles this actor may assign when changing a manageable member.
  List<CompanyRole> get assignableMemberRoles => switch (this) {
    CompanyRole.owner => CompanyRole.values.toList(growable: false),
    CompanyRole.admin => const [
      CompanyRole.manager,
      CompanyRole.employee,
    ],
    _ => const <CompanyRole>[],
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

  /// Owner, admin e manager gestiscono le categorie operative (la RLS resta il gate reale).
  bool get canManageCategories =>
      this == CompanyRole.owner ||
      this == CompanyRole.admin ||
      this == CompanyRole.manager;

  /// Owner, admin e manager gestiscono i documenti (la RLS resta il gate reale).
  bool get canManageDocuments =>
      this == CompanyRole.owner ||
      this == CompanyRole.admin ||
      this == CompanyRole.manager;
}
