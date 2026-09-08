# Billing Sandbox Processor Operations

## Purpose

Sandbox/Test operations only for Project Atlas Paddle Billing webhook
processing. This document does **not** cover production/live go-live,
provider reconciliation, or Flutter product flows.

Authoritative Premium entitlement comes from verified webhook apply, not from
checkout UI return pages.

## Safety defaults

Resting state (required after every exercise):

| Control | Expected resting value |
|---|---|
| `private.billing_runtime_config.checkout_enabled` | `false` |
| `private.billing_runtime_config.processor_enabled` | `false` |
| GitHub Actions variable `ATLAS_BILLING_PROCESSOR_SCHEDULE_ARMED` | `false` |

These controls are **independent**:

- **DB `processor_enabled`** — authoritative kill switch for
  `claim_next` / apply. When false, processor returns `outcome=disabled`.
- **GitHub `ATLAS_BILLING_PROCESSOR_SCHEDULE_ARMED`** — gates the *scheduled*
  cron job only. Manual `workflow_dispatch` on the schedule workflow still
  runs the HTTP job; the DB kill switch still prevents processing.

Never leave `processor_enabled=true` after a one-shot.

## Manual one-shot procedure

Exactly one eligible inbox event per approved one-shot.

1. Read-only pre-audit (runtime kill switches, company entitlement/billing,
   target event status, claim order).
2. Confirm the **exact next claimable** event id/type using current
   `claim_next` predicates/order (`provider_created_at ASC NULLS LAST`,
   `received_at ASC`, `id ASC`; verified; `received` or stale `processing`;
   `attempt_count < 5`; exclude simulator ids).
3. Require scheduler arming variable = `false`.
4. Require `processor_enabled=false` initially.
5. Guarded enable: update the single active paddle/test runtime row to
   `processor_enabled=true` only when already active, checkout state as
   approved for that exercise, and currently false. Require exactly one
   returned row.
6. Dispatch the sandbox **manual** processor workflow **exactly once**.
7. Observe that single GitHub Actions run to a terminal conclusion.
8. Force `processor_enabled=false` **regardless of success/failure**.
9. Post-audit: target event, sibling events, company entitlement, billing
   linkage. Prefer DB state over Actions conclusion if they disagree.
10. **Never** automatically retry on ambiguity or failure.

Do not print secrets, invoke headers, JWT, or raw webhook payloads.

## One POST / zero retry invariant

Both sandbox workflows must keep:

- exactly **one** authenticated HTTP POST per run
- `HTTP_POST_COUNT=1`
- `HTTP_RETRY_COUNT=0`
- no curl `--retry*` options

Manual dispatch workflow:
`.github/workflows/billing-webhook-processor-sandbox-dispatch.yml`

Schedule workflow:
`.github/workflows/billing-webhook-processor-sandbox-schedule.yml`

Legitimate HTTP 200 outcomes (aligned):

| Outcome | Actions result |
|---|---|
| `disabled` | success |
| `empty` | success |
| `processed` (valid shape) | success |
| `failed_finalized` (valid shape) | controlled failure (`exit 1`) |

Unknown outcome / malformed JSON / non-200 → failure.

## Stop / failure matrix

On any of:

- curl/transport failure
- ambiguous dispatch
- non-200 HTTP
- `failed_finalized`
- target remains `processing`
- target becomes `failed`
- wrong event claimed
- second/sibling event unexpectedly attempted (`attempt_count` / status change)
- entitlement regression
- billing linkage regression

Then:

| Action | Required |
|---|---|
| `processor_enabled` | force `false` immediately |
| scheduler arming | keep `false` |
| automatic retry | **forbidden** |
| evidence | preserve workflow run id + DB audit rows |
| further drain | **stop** (do not process the next event) |

## failed_finalized behavior

Under current architecture:

- Apply failure that is successfully fail-finalized yields HTTP 200 with
  `outcome=failed_finalized` and inbox `processing_status=failed`.
- Automatic `claim_next` **excludes** `failed` events (dead letter).
- `attempt_count < 5` does **not** mean failed events auto-retry; that gate
  applies to `received` / stale `processing` only.
- Fail finalizer does not implement automatic recovery.
- Manual UUID reclaim of `failed` exists in SQL but is **not** the scheduler
  path and is **out of scope** for 14C-2I.
- Operator recovery / provider reconciliation is **out of scope** for 14C-2I.

## Scheduler readiness checklist

Declare `SCHEDULER_SAFE_TO_ARM=YES` only when **all** are true:

- [ ] Local convergence tests green (created→activated equal watermark;
      transaction.completed after entitled)
- [ ] Remote known two-event drain proven for the Sandbox E2E company
- [ ] Global paddle/test `ELIGIBLE_RECEIVED_EVENT_COUNT = 0`
- [ ] Global paddle/test `STALE_PROCESSING_EVENT_COUNT = 0`
- [ ] No unresolved `failed` / `failed_finalized` inbox events in paddle/test
- [ ] Premium/billing stable after drain
- [ ] `processor_enabled` resting `false`
- [ ] `ATLAS_BILLING_PROCESSOR_SCHEDULE_ARMED` resting `false`
- [ ] Manual workflow response validator correct
- [ ] Schedule workflow response validator correct
- [ ] One POST / zero retry invariant confirmed
- [ ] Force-disable procedure documented (this file)
- [ ] `failed_finalized` response procedure documented (this file)

**Hard requirement:** `ELIGIBLE_RECEIVED_EVENT_COUNT` must equal **0** before
declaring scheduler readiness (`claim_next` is not company-scoped).

Do **not** permanently arm the scheduler as part of 14C-2I.

## Scheduler behavior

Current expected behavior when both arming variable and `processor_enabled`
are true:

- At most **one** event per processor invocation
- Cron cadence (`*/5 * * * *`) drains backlog across ticks (not an in-invoke
  batch loop)
- Claim order: oldest `provider_created_at`, then `received_at`, then `id`
- Stale `processing` leases (~10 minutes) can be reclaimed
- `failed` events do **not** automatically recover

## Out of scope / known debt

- Provider reconciliation / Paddle GET APIs
- Failed-event recovery automation
- Automatic retries of `failed` inbox rows
- Production/live environment
- Return-token / `browser_signal` checkout session closeout
- Continuous / permanent scheduler arming
