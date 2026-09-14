/**
 * Pure Paddle subscription snapshot normalization + prepare binding (D2-A).
 * No entitlement mapping; trialing is allowed through to apply RPC.
 */

import type { PaddleSubscriptionData } from "../_shared/providers/paddle/paddle_types.ts";
import {
  PADDLE_CUSTOMER_ID_RE,
  PADDLE_PRICE_ID_RE,
  PADDLE_SUBSCRIPTION_ID_RE,
} from "../_shared/providers/paddle/paddle_types.ts";
import type {
  NormalizedProviderSubscriptionSnapshot,
  PrepareBillingReconciliationResult,
} from "./types.ts";

export type NormalizeSubscriptionResult =
  | { ok: true; snapshot: NormalizedProviderSubscriptionSnapshot }
  | { ok: false; classification: "invalid_provider_response"; reason: string };

export type PrepareBindingResult =
  | { ok: true }
  | { ok: false; classification: "invalid_provider_response"; reason: string };

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** Fail-closed ISO-8601 / timestamptz parse; returns canonical ISO string. */
export function parseProviderTimestamp(raw: unknown): string | null {
  const s = asNonEmptyString(raw);
  if (!s) return null;
  const ms = Date.parse(s);
  if (!Number.isFinite(ms)) return null;
  return new Date(ms).toISOString();
}

/**
 * Convert Paddle GET subscription `data` into apply-ready fields.
 * Does not decide Premium/Free or reject trialing.
 */
export function normalizePaddleSubscriptionData(
  data: unknown,
): NormalizeSubscriptionResult {
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "subscription_data_missing",
    };
  }

  const sub = data as PaddleSubscriptionData;

  const externalSubscriptionId = asNonEmptyString(sub.id);
  if (
    !externalSubscriptionId ||
    !PADDLE_SUBSCRIPTION_ID_RE.test(externalSubscriptionId)
  ) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "subscription_id_invalid",
    };
  }

  const externalCustomerId = asNonEmptyString(sub.customer_id);
  if (
    !externalCustomerId || !PADDLE_CUSTOMER_ID_RE.test(externalCustomerId)
  ) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "customer_id_invalid",
    };
  }

  const status = asNonEmptyString(sub.status);
  if (!status) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "status_missing",
    };
  }
  const providerSubscriptionStatus = status.toLowerCase();

  const providerUpdatedAt = parseProviderTimestamp(sub.updated_at);
  if (!providerUpdatedAt) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "updated_at_invalid",
    };
  }

  const items = sub.items;
  if (!Array.isArray(items) || items.length < 1) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "price_missing",
    };
  }
  const first = items[0];
  if (first === null || typeof first !== "object") {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "price_missing",
    };
  }
  const priceObj = (first as { price?: unknown }).price;
  if (priceObj === null || typeof priceObj !== "object") {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "price_missing",
    };
  }
  const priceId = asNonEmptyString((priceObj as { id?: unknown }).id);
  if (!priceId || !PADDLE_PRICE_ID_RE.test(priceId)) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "price_invalid",
    };
  }

  let currentPeriodStart: string | null = null;
  let currentPeriodEnd: string | null = null;
  const period = sub.current_billing_period;
  if (period !== undefined && period !== null) {
    if (typeof period !== "object" || Array.isArray(period)) {
      return {
        ok: false,
        classification: "invalid_provider_response",
        reason: "period_invalid",
      };
    }
    if (period.starts_at !== undefined && period.starts_at !== null) {
      currentPeriodStart = parseProviderTimestamp(period.starts_at);
      if (!currentPeriodStart) {
        return {
          ok: false,
          classification: "invalid_provider_response",
          reason: "period_start_invalid",
        };
      }
    }
    if (period.ends_at !== undefined && period.ends_at !== null) {
      currentPeriodEnd = parseProviderTimestamp(period.ends_at);
      if (!currentPeriodEnd) {
        return {
          ok: false,
          classification: "invalid_provider_response",
          reason: "period_end_invalid",
        };
      }
    }
  }

  let canceledAt: string | null = null;
  if (sub.canceled_at !== undefined && sub.canceled_at !== null) {
    canceledAt = parseProviderTimestamp(sub.canceled_at);
    if (!canceledAt) {
      return {
        ok: false,
        classification: "invalid_provider_response",
        reason: "canceled_at_invalid",
      };
    }
  }

  let cancelAtPeriodEnd = false;
  const scheduled = sub.scheduled_change;
  if (scheduled !== undefined && scheduled !== null) {
    if (typeof scheduled !== "object" || Array.isArray(scheduled)) {
      return {
        ok: false,
        classification: "invalid_provider_response",
        reason: "scheduled_change_invalid",
      };
    }
    const action = asNonEmptyString(scheduled.action);
    if (action !== null && action.toLowerCase() === "cancel") {
      cancelAtPeriodEnd = true;
    }
  }

  return {
    ok: true,
    snapshot: {
      external_subscription_id: externalSubscriptionId,
      external_customer_id: externalCustomerId,
      external_price_id: priceId,
      provider_subscription_status: providerSubscriptionStatus,
      current_period_start: currentPeriodStart,
      current_period_end: currentPeriodEnd,
      cancel_at_period_end: cancelAtPeriodEnd,
      canceled_at: canceledAt,
      provider_updated_at: providerUpdatedAt,
    },
  };
}

/**
 * Require exact subscription + customer binding to prepare anchors.
 * Price is intentionally NOT compared (catalog gate is apply-side).
 */
export function assertPrepareProviderBinding(
  prepare: Pick<
    PrepareBillingReconciliationResult,
    "external_subscription_id" | "external_customer_id"
  >,
  snapshot: Pick<
    NormalizedProviderSubscriptionSnapshot,
    "external_subscription_id" | "external_customer_id"
  >,
): PrepareBindingResult {
  if (
    snapshot.external_subscription_id !== prepare.external_subscription_id
  ) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "subscription_id_mismatch",
    };
  }
  if (snapshot.external_customer_id !== prepare.external_customer_id) {
    return {
      ok: false,
      classification: "invalid_provider_response",
      reason: "customer_id_mismatch",
    };
  }
  return { ok: true };
}
