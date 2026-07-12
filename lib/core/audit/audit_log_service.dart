/// Evento di audit per operazioni importanti (persistenza in Fase 1+).
class AuditEvent {
  const AuditEvent({
    required this.action,
    required this.entityType,
    this.entityId,
    this.metadata,
    this.timestamp,
  });

  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, Object?>? metadata;
  final DateTime? timestamp;
}

/// Contratto per la registrazione degli audit log.
/// L'implementazione concreta verrà aggiunta in Fase 1+.
abstract interface class AuditLogService {
  Future<void> log(AuditEvent event);
}
