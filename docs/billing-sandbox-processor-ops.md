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

Processor and scheduler kill switches remain authoritative. Documentation
disposition never overrides them.

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

Unexpected `failed` / `failed_finalized` inbox rows (not an exact match in the
operator-accepted test dead-letter registry below) require operator
investigation. Do **not** treat them as routine recovery candidates. Do **not**
reset, requeue, or delete inbox rows as routine recovery. Stop automatic
processing / readiness decisions until disposition is explicit.

## failed_finalized behavior

Under current architecture:

- Apply failure that is successfully fail-finalized yields HTTP 200 with
  `outcome=failed_finalized` and inbox `processing_status=failed`.
- Automatic `claim_next` **excludes** `failed` events (dead letter).
- The processor **never** automatically retries `failed_finalized` / `failed`
  inbox events.
- `attempt_count < 5` does **not** mean failed events auto-retry; that gate
  applies to `received` / stale `processing` only.
- Fail finalizer does not implement automatic recovery.
- Manual UUID reclaim of `failed` exists in SQL but is **not** the scheduler
  path and is **out of scope** for 14C-2I.
- Operator recovery / provider reconciliation is **out of scope** for 14C-2I.
- An `OPERATOR_ACCEPTED_TEST_DEAD_LETTER` classification is an **operator
  disposition only**. It does **not** change DB `processing_status`, does
  **not** clear `error_sanitized`, and does **not** make the row claimable
  again.

## OPERATOR_ACCEPTED_TEST_DEAD_LETTER

`OPERATOR_ACCEPTED_TEST_DEAD_LETTER` is a **strict** operator disposition term.
It is **not** a blanket exception for failed events.

A paddle/test inbox row may be classified
`OPERATOR_ACCEPTED_TEST_DEAD_LETTER` **only when all** of the following are
true:

- `provider_environment=test` (sandbox/test only)
- exact inbox event UUID recorded
- exact `external_event_id` recorded
- `event_type` recorded
- failure / error code recorded
- provenance conclusively proven
- failure was intentionally induced or expected by a controlled test
- current production behavior is correct
- no product defect remains
- no retry / reprocessing is required
- no entitlement / data corruption exists
- event is excluded from the normal claim path (`failed` dead letter)
- preserving it has audit / debug value
- operator explicitly reviewed and accepted it
- no pending remediation exists

Unknown, unexplained, real-user, production/live, or potentially defective
failed events **MUST NOT** qualify.

## Operator-accepted test dead letters

Registry of operator-reviewed paddle/test dead letters (14C-2I Phase I6/I7).
Exact-match only. Mismatch on id, external id, type, error, status, or
provenance means the row is **unresolved** and blocks scheduler readiness.

### A — L-E5 synthetic LE3 fixture

| Field | Value |
|---|---|
| environment | paddle / test |
| inbox_event_id | `b59de26a-6a59-4e27-8edc-2b53fb95862f` |
| external_event_id | `evt_atlasle5000000000000000000` |
| event_type | `transaction.completed` |
| expected error | `ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD` |
| provenance | 14C-2G L-E5 synthetic LE3 fixture |
| reason | synthetic customer/subscription identifiers have 25-char suffixes instead of required 26 chars; intentionally preserved audit dead-letter |
| disposition | `OPERATOR_ACCEPTED_TEST_DEAD_LETTER` |
| remediation | none |
| retry / requeue | prohibited / not required |
| entitlement regression | none |

### B — K-C2 intentional apply-fail fixture

| Field | Value |
|---|---|
| environment | paddle / test |
| inbox_event_id | `e6ecbb21-8f8a-46db-becb-b58ec727fc18` |
| external_event_id | `evt_zzzzatlas14c2fkb1pos000001` |
| event_type | `subscription.activated` |
| expected error | `ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD` |
| provenance | 14C-2F K-C2 intentional apply-fail/finalize fixture |
| reason | intentionally incomplete payload: missing `data.status` and `data.customer_id` |
| disposition | `OPERATOR_ACCEPTED_TEST_DEAD_LETTER` |
| remediation | none |
| retry / requeue | prohibited / not required |
| entitlement regression | none |

### C — K-D2/K-D3 intentional UNLINKED fixture

| Field | Value |
|---|---|
| environment | paddle / test |
| inbox_event_id | `f818e842-d0f5-4614-bf34-a9625e0a8827` |
| external_event_id | `evt_zzzzatlas14c2fkd1unl000001` |
| event_type | `subscription.activated` |
| expected error | `ATLAS_PROVIDER_EVENT_UNLINKED` |
| provenance | 14C-2F K-D2/K-D3 intentional UNLINKED fixture |
| reason | P0/P1 miss + intentionally incomplete P2 first-link proof |
| disposition | `OPERATOR_ACCEPTED_TEST_DEAD_LETTER` |
| remediation | none |
| retry / requeue | prohibited / not required |
| entitlement regression | none |

## Scheduler readiness checklist

Declare `SCHEDULER_SAFE_TO_ARM=YES` only when **all** are true (fail-closed):

- [ ] `checkout_enabled=false`
- [ ] `processor_enabled` resting state appropriate for the arming procedure
      (resting `false` before any guarded enable)
- [ ] `ATLAS_BILLING_PROCESSOR_SCHEDULE_ARMED` currently `false` before any
      arming action
- [ ] Global paddle/test eligible verified queue = `0`
      (`ELIGIBLE_RECEIVED_EVENT_COUNT = 0`; `claim_next` is not company-scoped)
- [ ] Global paddle/test stale processing count = `0`
- [ ] No unexpected `received` / `processing` paddle/test events
- [ ] No **unresolved** `failed` / `failed_finalized` paddle/test inbox events
- [ ] Every retained paddle/test `failed` row **exactly** matches an
      `OPERATOR_ACCEPTED_TEST_DEAD_LETTER` registry entry (id +
      `external_event_id` + `event_type` + expected error). Registry matches
      are operator-disposed, **not** unresolved.
- [ ] No product-fix / manual-investigation failed rows remain
- [ ] Local convergence tests green / present on develop
      (created→activated equal watermark; transaction.completed after entitled)
- [ ] Remote known two-event drain proven for the Sandbox E2E company
- [ ] Manual and schedule workflow response validators aligned
- [ ] One POST / zero retry invariant confirmed
- [ ] Entitlement / linkage state healthy after drain
- [ ] Force-disable procedure documented (this file)
- [ ] `failed_finalized` response procedure documented (this file)

**Unresolved failed event (blocks `SCHEDULER_SAFE_TO_ARM=YES`):** any
paddle/test `failed` / `failed_finalized` row that is absent from the
registry, mismatched against the registry, newly appeared, has a different
error / status / event id, has unknown provenance, or still requires
remediation.

This rule is **fail-closed**. It is **not** a broad allowance that “failed
events are allowed.”

If any checklist condition fails: `SCHEDULER_SAFE_TO_ARM=NO`.

After documentation review/acceptance of this dead-letter policy, a **fresh
read-only readiness audit** is still required before any arming decision.
This document does **not** arm the scheduler. Actual scheduler arming remains
a separate explicit operator decision.

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
