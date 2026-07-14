/// Azienda (tenant) dell'applicazione.
class Company {
  const Company({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final DateTime createdAt;
  final DateTime updatedAt;
}
