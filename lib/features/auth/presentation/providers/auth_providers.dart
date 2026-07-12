import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stato di autenticazione stub per Fase 0.
/// Verrà sostituito con Supabase Auth in Fase 1.
final authStateProvider = StateProvider<bool>((ref) => false);

void signInStub(WidgetRef ref) {
  ref.read(authStateProvider.notifier).state = true;
}

void signOutStub(WidgetRef ref) {
  ref.read(authStateProvider.notifier).state = false;
}
