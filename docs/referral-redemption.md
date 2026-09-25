# Referral reward redemption (Step 18B)

## Product rule

- **1 referral reward = 1 calendar Premium month** (not 30 days, not “one billing interval”).
- Provider mechanism (Step 18A locked): extend Paddle `next_billed_at` with
  `proration_billing_mode: do_not_bill`.
- Atlas **must not** invent Premium by mutating entitlement locally.

Rejected alternatives:

- Customer credit balance (Paddle: not promotional/referral credits)
- Subscription 100% discount (interval-coupled; annual would grant a free year)

## Calendar months

UTC calendar add with end-of-month clamp (PostgreSQL `+ make_interval(months => N)` /
`addCalendarMonthsUtc`):

| Input | +N | Result |
|-------|----|--------|
| 2026-01-31 | 1 | 2026-02-28 |
| 2028-01-31 | 1 | 2028-02-29 |
| 2026-03-31 | 1 | 2026-04-30 |
| 2026-10-15 | 3 | 2027-01-15 |

Multi-month is a **single step** from the original day (Jan 31 + 2 → Mar 31).

## Kill switch

`private.billing_runtime_config.referral_redemption_enabled` **DEFAULT FALSE**.

Independent of `checkout_enabled` / `processor_enabled`.
While false: **zero** outbound Paddle redemption calls and **zero** new redemption
mutation (`evaluate_referral_auto_redemption` / claim both fail closed).

## Trigger model (AUTO)

`REDEMPTION_TRIGGER_MODEL=AUTO`.

A qualified reward redeems automatically once the company has an eligible active
Paddle subscription. No owner manual redeem is required for the happy path.

Local foundation (18B):

1. Authoritative webhook apply or owner reconciliation updates `company_billing`
2. Exact-target confirm trigger may close an open operation (no +N again)
3. Processor / reconcile best-effort invokes `billing-referral-redeem-paddle`
   only when `evaluate_referral_auto_redemption_server` says `should_invoke_outbound`
4. Edge claim creates at most one open operation; open ops are healed, not duplicated

Recursion safety: redemption-generated `subscription.updated` confirms exact target;
with no remaining pending rewards, evaluate returns `no_pending` → **no** second PATCH.

Near-renewal (inclusive 30 minutes): `current_period_end <= now()+30m` →
`ATLAS_REFERRAL_NEAR_RENEWAL` (server-derived; client cannot bypass).

## State machine

**Operation** (`private.billing_referral_redemption_operations`):
`claimed → previewing → ready_to_apply → provider_accepted → confirmed`
Branches: `needs_reconcile`, `retryable_failed`, `blocked`, `terminal_failed`.

**Reward**: `pending → applying → redeemed` (never void on transient failure).

At most **one open operation per company** (partial unique index).

## Batch

All currently pending rewards for a company are claimed into **one** operation and
applied with **one** PATCH:

`target = add_calendar_months(expected_old_next_billed_at, N)`.

## Lost response / idempotency

Atlas does **not** rely on a Paddle idempotency header.

Defense:

1. `expected_old_next_billed_at` + `target_next_billed_at` (immutable after claim)
2. Open operation identity
3. GET before retry
4. Exact target match only (never `live >= target`, never `target = live + N`)

| Live `next_billed_at` / period end | Action |
|------------------------------------|--------|
| == target | provider accepted / confirm |
| == expected_old | safe retry same op |
| third value | `needs_reconcile` / conflict — **no PATCH** |

## Confirmation

Rewards become `redeemed` only after authoritative billing apply updates
`company_billing.current_period_end` to the **exact** target **and** moves a
provider fence (`last_provider_subscription_updated_at` and/or state fingerprint).
Period-end-only updates do **not** confirm (spoof resistance). Clients have
**no** UPDATE grant on `private.company_billing`.

- Outbound HTTP 200 alone is **not** enough.
- `transaction.completed` does **not** confirm (does not move period end).

Entitlement alignment: Atlas Premium uses `provider_access_ends_at` from
`current_billing_period.ends_at`. Paddle billing-date changes are expected to move
that period end with `next_billed_at`; confirmation keys off that Atlas field.

## Eligibility (v1)

Redeem only when linked **active** entitled Paddle sub, not past_due, not canceled,
not scheduled-to-cancel, not internal-trial-only, and next bill **> 30 minutes** away.

Otherwise rewards stay **pending** and become eligible again after recovery
(past_due→active, scheduled_cancel cleared, unlink→relink, free→paid active).
Fully canceled does **not** reactivate; a new active subscription is a new lifecycle
(stale open ops protected by provider subscription snapshot).

## Edge Function (local only in 18B)

`supabase/functions/billing-referral-redeem-paddle/`

- Invoke secret: `ATLAS_REFERRAL_REDEEM_INVOKE_SECRET` / header `x-atlas-referral-redeem-secret`
- Preview fail-closed, then PATCH minimal body
- **Not deployed** in this step

## Owner UI

Overview shows pending / applying / redeemed / blocked copy.
Owner **Riprova** only for retryable stuck states. Members: aggregates only.

## Activation (NOT this step)

Remote migration deploy, Edge deploy, enabling `referral_redemption_enabled`,
processor/scheduler, and sandbox E2E against live Paddle require separate authorization.
