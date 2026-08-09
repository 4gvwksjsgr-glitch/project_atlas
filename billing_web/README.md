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
entitlement proof. Authoritative Premium entitlement comes only from verified
webhook / reconciliation (future step).
