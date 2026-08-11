/** Post-signature payload validation for Paddle sandbox webhooks. */

import {
  type EventClassification,
  PADDLE_EVENT_ID_RE,
  PADDLE_SUBSCRIPTION_ID_RE,
  SUPPORTED_EVENT_TYPES,
  type SupportedEventType,
  type VerifiedWebhookPayload,
} from "./types.ts";

function isSupportedEventType(value: string): value is SupportedEventType {
  return (SUPPORTED_EVENT_TYPES as readonly string[]).includes(value);
}

/**
 * Strict RFC3339 date-time gate: complete date-time with Z or ±HH:MM offset.
 * Rejects date-only, missing/malformed timezone, trailing garbage, and
 * impossible calendar/time values. Fractional seconds allowed.
 */
const RFC3339_RE =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

function daysInMonth(year: number, month: number): number {
  // month: 1-12
  if (month === 2) {
    const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    return leap ? 29 : 28;
  }
  if (month === 4 || month === 6 || month === 9 || month === 11) return 30;
  return 31;
}

export function isRfc3339DateTime(value: string): boolean {
  if (typeof value !== "string" || value.length === 0) return false;
  // No whitespace / trim-normalization; reject leading/trailing space.
  if (value.trim() !== value || /\s/.test(value)) return false;

  const m = RFC3339_RE.exec(value);
  if (!m) return false;

  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  const hour = Number(m[4]);
  const minute = Number(m[5]);
  const second = Number(m[6]);
  const tz = m[8]!;

  if (!Number.isInteger(year) || year < 1) return false;
  if (month < 1 || month > 12) return false;
  if (hour > 23 || minute > 59 || second > 59) return false;
  if (day < 1 || day > daysInMonth(year, month)) return false;

  if (tz !== "Z") {
    const oh = Number(tz.slice(1, 3));
    const om = Number(tz.slice(4, 6));
    if (oh > 23 || om > 59) return false;
  }

  const ms = Date.parse(value);
  if (!Number.isFinite(ms)) return false;

  // Semantic round-trip: reconstructed instant must match parsed components
  // for Z (UTC). For numeric offsets, verify Date representation is finite
  // and that formatting the instant back through the same offset components
  // does not shift the civil time (reject Date-invalid edge cases).
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) return false;

  if (tz === "Z") {
    if (d.getUTCFullYear() !== year) return false;
    if (d.getUTCMonth() + 1 !== month) return false;
    if (d.getUTCDate() !== day) return false;
    if (d.getUTCHours() !== hour) return false;
    if (d.getUTCMinutes() !== minute) return false;
    if (d.getUTCSeconds() !== second) return false;
    return true;
  }

  // Offset: apply offset to recover civil time from UTC instant.
  const sign = tz.charAt(0) === "-" ? -1 : 1;
  const oh = Number(tz.slice(1, 3));
  const om = Number(tz.slice(4, 6));
  const offsetMin = sign * (oh * 60 + om);
  const localMs = ms + offsetMin * 60_000;
  const local = new Date(localMs);
  if (local.getUTCFullYear() !== year) return false;
  if (local.getUTCMonth() + 1 !== month) return false;
  if (local.getUTCDate() !== day) return false;
  if (local.getUTCHours() !== hour) return false;
  if (local.getUTCMinutes() !== minute) return false;
  if (local.getUTCSeconds() !== second) return false;
  return true;
}

function extractSubscriptionId(
  eventType: string,
  data: unknown,
): string | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const obj = data as Record<string, unknown>;

  if (eventType.startsWith("subscription.")) {
    const id = obj.id;
    if (typeof id === "string" && PADDLE_SUBSCRIPTION_ID_RE.test(id)) {
      return id;
    }
    return null;
  }

  if (eventType.startsWith("transaction.")) {
    const sub = obj.subscription_id;
    if (sub === null || sub === undefined) return null;
    if (typeof sub === "string" && PADDLE_SUBSCRIPTION_ID_RE.test(sub)) {
      return sub;
    }
    return null;
  }

  return null;
}

export type ParseVerifiedPayloadResult =
  | { ok: true; value: VerifiedWebhookPayload }
  | { ok: false; reason: "invalid_json" | "invalid_shape" };

export function parseVerifiedWebhookPayload(
  rawText: string,
): ParseVerifiedPayloadResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    return { ok: false, reason: "invalid_json" };
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { ok: false, reason: "invalid_shape" };
  }

  const root = parsed as Record<string, unknown>;
  const eventId = root.event_id;
  const eventType = root.event_type;
  const occurredAt = root.occurred_at;

  if (typeof eventId !== "string" || !PADDLE_EVENT_ID_RE.test(eventId)) {
    return { ok: false, reason: "invalid_shape" };
  }
  if (
    typeof eventType !== "string" ||
    eventType.trim() === "" ||
    eventType.length > 128
  ) {
    return { ok: false, reason: "invalid_shape" };
  }
  if (typeof occurredAt !== "string" || !isRfc3339DateTime(occurredAt)) {
    return { ok: false, reason: "invalid_shape" };
  }

  const classification: EventClassification = isSupportedEventType(eventType)
    ? "supported"
    : "ignored";

  const externalSubscriptionId = extractSubscriptionId(eventType, root.data);

  return {
    ok: true,
    value: {
      event_id: eventId,
      event_type: eventType,
      occurred_at: occurredAt,
      classification,
      external_subscription_id: externalSubscriptionId,
      payload_json: root,
    },
  };
}
