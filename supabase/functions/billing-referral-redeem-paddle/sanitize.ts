/**
 * Pure validation / normalization helpers for billing-referral-redeem-paddle.
 * No network, no logging of bodies.
 */

import { AtlasHttpError, defaultMessageForCode } from "../_shared/errors.ts";
import { FORBIDDEN_COMMERCE_FIELDS, isUuid } from "../_shared/http.ts";
import { addCalendarMonthsUtc } from "../_shared/providers/paddle/calendar_months.ts";
import type { PaddleSubscriptionData } from "../_shared/providers/paddle/paddle_types.ts";
import { PADDLE_SUBSCRIPTION_ID_RE } from "../_shared/providers/paddle/paddle_types.ts";
import {
  type ClaimReferralRedemptionRow,
  type OpenReferralRedemptionRow,
  type OperationContext,
  REFERRAL_ERROR,
  type RedeemRequestBody,
} from "./types.ts";

function invalidRequest(message = defaultMessageForCode("ATLAS_INVALID_REQUEST")) {
  return new AtlasHttpError(400, "ATLAS_INVALID_REQUEST", message);
}

/** Parse `{ "company_id": "<uuid>", "mode": "auto" | "owner_retry" }` only. */
export function parseRedeemBody(bytes: Uint8Array): RedeemRequestBody {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_JSON",
      defaultMessageForCode("ATLAS_INVALID_JSON"),
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_JSON",
      defaultMessageForCode("ATLAS_INVALID_JSON"),
    );
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw invalidRequest();
  }
  const obj = parsed as Record<string, unknown>;
  for (const key of Object.keys(obj)) {
    if (
      (FORBIDDEN_COMMERCE_FIELDS as readonly string[]).includes(
        key.toLowerCase(),
      )
    ) {
      throw invalidRequest("Request contains forbidden fields");
    }
    if (key !== "company_id" && key !== "mode") {
      throw invalidRequest("Request contains unexpected fields");
    }
  }
  if (!("company_id" in obj)) {
    throw new AtlasHttpError(
      400,
      "ATLAS_COMPANY_ID_REQUIRED",
      defaultMessageForCode("ATLAS_COMPANY_ID_REQUIRED"),
    );
  }
  const companyId = obj.company_id;
  if (typeof companyId !== "string" || !isUuid(companyId)) {
    throw invalidRequest("company_id must be a UUID");
  }
  const mode = obj.mode;
  if (mode !== "auto" && mode !== "owner_retry") {
    throw invalidRequest("mode must be auto or owner_retry");
  }
  return { company_id: companyId.toLowerCase(), mode };
}

const PG_UTC_TS_RE =
  /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(\.\d{1,9})?(Z|[+-]00(?::?00)?)$/;

/**
 * Normalize a UTC timestamp (PostgREST `+00:00` or `Z`) to RFC3339 `Z`,
 * preserving fractional precision so the PATCHed instant equals the SQL
 * target exactly. Non-UTC offsets and unparseable values return null.
 */
export function toRfc3339Utc(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const m = PG_UTC_TS_RE.exec(value.trim());
  if (!m) return null;
  const out = `${m[1]}T${m[2]}${m[3] ?? ""}Z`;
  const ms = Date.parse(out);
  if (Number.isNaN(ms)) return null;
  if (new Date(ms).toISOString().slice(0, 10) !== m[1]) return null;
  return out;
}

export function sameInstant(a: string | null, b: string | null): boolean {
  if (a === null || b === null) return false;
  const ma = Date.parse(a);
  const mb = Date.parse(b);
  return !Number.isNaN(ma) && !Number.isNaN(mb) && ma === mb;
}

/**
 * Validate server-derived operation fields before any provider call.
 * Target must equal expected_old + reward_count calendar months (UTC).
 */
function buildContext(input: {
  operation_id: unknown;
  status: unknown;
  reward_count: unknown;
  expected_old: unknown;
  target: unknown;
  subscription_id: unknown;
  new_claim: boolean;
}): OperationContext | null {
  if (typeof input.operation_id !== "string" || !isUuid(input.operation_id)) {
    return null;
  }
  if (typeof input.status !== "string" || input.status.length === 0) {
    return null;
  }
  const n = input.reward_count;
  if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || n > 5) {
    return null;
  }
  const oldTs = toRfc3339Utc(input.expected_old);
  const targetTs = toRfc3339Utc(input.target);
  if (!oldTs || !targetTs) return null;
  if (Date.parse(targetTs) <= Date.parse(oldTs)) return null;
  if (!sameInstant(addCalendarMonthsUtc(oldTs, n), targetTs)) return null;
  const sub = typeof input.subscription_id === "string"
    ? input.subscription_id.trim()
    : "";
  if (!PADDLE_SUBSCRIPTION_ID_RE.test(sub)) return null;
  return {
    operation_id: input.operation_id,
    status: input.status,
    reward_count: n,
    expected_old_next_billed_at: oldTs,
    target_next_billed_at: targetTs,
    provider_subscription_id: sub,
    new_claim: input.new_claim,
  };
}

export function contextFromClaim(
  row: ClaimReferralRedemptionRow,
): OperationContext | null {
  return buildContext({
    operation_id: row.operation_id,
    status: row.operation_status,
    reward_count: row.reward_count,
    expected_old: row.expected_old_next_billed_at,
    target: row.target_next_billed_at,
    subscription_id: row.provider_subscription_id,
    new_claim: row.outcome === "claimed",
  });
}

export function contextFromOpen(
  row: OpenReferralRedemptionRow,
  newClaim: boolean,
): OperationContext | null {
  return buildContext({
    operation_id: row.id,
    status: row.status,
    reward_count: row.reward_count,
    expected_old: row.expected_old_next_billed_at,
    target: row.target_next_billed_at,
    subscription_id: row.provider_subscription_id_snapshot,
    new_claim: newClaim,
  });
}

/** Live next billing instant: data.next_billed_at, else current period end. */
export function readLiveNextBilledAt(
  data: PaddleSubscriptionData,
): string | null {
  const next = typeof data.next_billed_at === "string"
    ? data.next_billed_at
    : null;
  if (next !== null && !Number.isNaN(Date.parse(next))) return next;
  const ends = data.current_billing_period?.ends_at;
  if (typeof ends === "string" && !Number.isNaN(Date.parse(ends))) return ends;
  return null;
}

/**
 * Live Paddle state that must keep rewards pending (abort, no PATCH).
 * Returns the block code, or null when the subscription is active and clean.
 */
export function liveBlockReason(data: PaddleSubscriptionData): string | null {
  const status = typeof data.status === "string" ? data.status : null;
  if (status === "past_due") return REFERRAL_ERROR.PAST_DUE;
  if (status === "canceled") return REFERRAL_ERROR.CANCELED;
  if (status === "trialing") return REFERRAL_ERROR.TRIALING;
  if (status !== "active") return REFERRAL_ERROR.NOT_ACTIVE;
  const change = data.scheduled_change;
  if (change !== null && change !== undefined) {
    return change.action === "cancel"
      ? REFERRAL_ERROR.SCHEDULED_CANCEL
      : REFERRAL_ERROR.NOT_ACTIVE;
  }
  return null;
}
