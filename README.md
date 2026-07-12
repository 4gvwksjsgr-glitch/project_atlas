# Project Atlas

Piattaforma SaaS multi-tenant per aziende. Stack: Flutter, Material 3, Riverpod, GoRouter, Supabase.

## Setup locale

1. Clona il repository
2. Copia il file ambiente:

```bash
cp .env.example .env
```

3. Compila `.env` con le credenziali Supabase del tuo progetto
4. Installa le dipendenze e avvia l'app:

```bash
flutter pub get
flutter run -d chrome
```

## Branch strategy

| Branch | Scopo |
|--------|-------|
| `main` | Produzione |
| `develop` | Integrazione continua |
| `feature/*` | Sviluppo feature |

Flusso: `feature/*` → `develop` → `main`

Convenzione commit: [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `docs:`).

## Comandi utili

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
flutter build web
```

## Architettura

- **Clean Architecture** + **Feature First**
- `lib/core/` — infrastruttura (config, router, logging, rete)
- `lib/shared/` — codice condiviso tra feature (widgets, helpers, extensions, constants)
- `lib/features/` — moduli di dominio

