# Atlas billing_web — dedicated Paddle payment surface

Static HTTPS pages for Paddle Billing sandbox checkout.

## Purpose

Dedicated payment site for:

- `/billing/checkout`
- `/billing/return`

This site is separate from the Flutter application. It never grants Premium and
never holds server credentials.

## Local build

Disabled checkout (safe local default):

```bash
node scripts/build.mjs --dev
```

Production-style sandbox build (requires a sandbox **client-side** token
matching `^test_[a-zA-Z0-9]{27}$` — never commit it; no silent trim):

```bash
PADDLE_SANDBOX_CLIENT_TOKEN=test_... node scripts/build.mjs
```

Output: `billing_web/dist/` (gitignored).

## Future Cloudflare Pages

| Setting | Value |
|---|---|
| Root directory | `billing_web` |
| Build command | `node scripts/build.mjs` |
| Build output directory | `dist` |
| Public build variable | `PADDLE_SANDBOX_CLIENT_TOKEN` |

## Credential rules

- `PADDLE_SANDBOX_CLIENT_TOKEN` is a **public / browser-side** sandbox client token.
- `PADDLE_SANDBOX_API_KEY` must **NEVER** be placed here.
- `SUPABASE_SERVICE_ROLE_KEY` must **NEVER** be placed here.

## Entitlement

Checkout completion (overlay events, redirects, query parameters) is **not**
entitlement proof. This site does **not** grant Premium and does **not**
refresh Atlas subscription state after checkout.

Authoritative Premium state comes from verified server-side billing only:

- webhook ingest (`billing-webhook-paddle`) + processor apply
  (`billing-webhook-processor-paddle`); and/or
- owner-initiated Paddle sandbox reconciliation
  (`billing-reconciliation-paddle`).

Checkout / browser success remains UX-only. Return-token / `browser_signal`
session closeout product wiring remains deferred.
