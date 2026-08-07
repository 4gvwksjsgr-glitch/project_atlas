/**
 * Shared HTTP helpers for Atlas Edge Functions.
 * Pure helpers are exported for unit tests (no network).
 */

import {
  atlasErrorBody,
  type AtlasErrorCode,
  AtlasHttpError,
  defaultMessageForCode,
} from "./errors.ts";

export const MAX_BODY_BYTES = 4 * 1024; // 4 KiB
export const MAX_IDEMPOTENCY_KEY_CHARS = 128;
export const SUCCESS_SCHEMA_VERSION = 1 as const;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Commerce fields clients must never send (server-owned). */
export const FORBIDDEN_COMMERCE_FIELDS = [
  "offer",
  "offer_code",
  "plan",
  "plan_code",
  "atlas_plan_code",
  "price",
  "price_id",
  "external_price_id",
  "amount",
  "currency",
  "environment",
  "provider_environment",
  "actor",
  "actor_user_id",
  "user_id",
  "initiated_by_user_id",
] as const;

export interface CorsDecision {
  ok: boolean;
  /** Allow-Origin value when ok; undefined for no-Origin native requests. */
  allowOrigin?: string;
  /** True when request had Origin and it was allowed. */
  hasAllowedOrigin: boolean;
}

export function parseCorsAllowlist(raw: string | undefined | null): string[] {
  if (!raw) return [];
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && s !== "*");
}

/**
 * CORS origin check. Never returns `*` — credentials/auth require exact origin.
 * Requests without Origin are allowed (native clients); caller still requires JWT.
 */
export function decideCors(
  originHeader: string | null,
  allowlist: readonly string[],
): CorsDecision {
  if (
    originHeader === null || originHeader === undefined ||
    originHeader.trim() === ""
  ) {
    return { ok: true, hasAllowedOrigin: false };
  }
  const origin = originHeader.trim();
  if (allowlist.includes(origin)) {
    return { ok: true, allowOrigin: origin, hasAllowedOrigin: true };
  }
  return { ok: false, hasAllowedOrigin: false };
}

export function corsHeaders(allowOrigin: string | undefined): HeadersInit {
  const headers: Record<string, string> = {
    "Vary": "Origin",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, content-type, idempotency-key, x-client-info, apikey",
    "Access-Control-Max-Age": "86400",
  };
  if (allowOrigin) {
    headers["Access-Control-Allow-Origin"] = allowOrigin;
    headers["Access-Control-Allow-Credentials"] = "true";
  }
  return headers;
}

/** Deterministic OPTIONS preflight response. */
export function buildOptionsResponse(
  originHeader: string | null,
  allowlist: readonly string[],
  correlationId: string,
): Response {
  const decision = decideCors(originHeader, allowlist);
  if (!decision.ok) {
    return jsonErrorResponse(
      403,
      "ATLAS_CORS_ORIGIN_DENIED",
      defaultMessageForCode("ATLAS_CORS_ORIGIN_DENIED"),
      false,
      correlationId,
      corsHeaders(undefined),
    );
  }
  return new Response(null, {
    status: 204,
    headers: corsHeaders(decision.allowOrigin),
  });
}

export function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

export function requireIdempotencyKey(
  headerValue: string | null,
): string {
  if (headerValue === null || headerValue === undefined) {
    throw new AtlasHttpError(
      400,
      "ATLAS_IDEMPOTENCY_KEY_REQUIRED",
      defaultMessageForCode("ATLAS_IDEMPOTENCY_KEY_REQUIRED"),
    );
  }
  // Reject ASCII control characters on the raw value before any trim.
  for (let i = 0; i < headerValue.length; i++) {
    const code = headerValue.charCodeAt(i);
    if (code <= 0x1f || code === 0x7f) {
      throw new AtlasHttpError(
        400,
        "ATLAS_INVALID_IDEMPOTENCY_KEY",
        defaultMessageForCode("ATLAS_INVALID_IDEMPOTENCY_KEY"),
      );
    }
  }
  const trimmed = headerValue.trim();
  if (trimmed.length === 0) {
    throw new AtlasHttpError(
      400,
      "ATLAS_IDEMPOTENCY_KEY_REQUIRED",
      defaultMessageForCode("ATLAS_IDEMPOTENCY_KEY_REQUIRED"),
    );
  }
  if (trimmed.length > MAX_IDEMPOTENCY_KEY_CHARS) {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_IDEMPOTENCY_KEY",
      defaultMessageForCode("ATLAS_INVALID_IDEMPOTENCY_KEY"),
    );
  }
  // Opaque printable ASCII (no spaces — already rejected via control/space checks)
  if (!/^[\x21-\x7E]+$/.test(trimmed)) {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_IDEMPOTENCY_KEY",
      defaultMessageForCode("ATLAS_INVALID_IDEMPOTENCY_KEY"),
    );
  }
  return trimmed;
}

export function requireJsonContentType(contentType: string | null): void {
  if (!contentType) {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_CONTENT_TYPE",
      defaultMessageForCode("ATLAS_INVALID_CONTENT_TYPE"),
    );
  }
  const media = contentType.split(";")[0]!.trim().toLowerCase();
  if (media !== "application/json") {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_CONTENT_TYPE",
      defaultMessageForCode("ATLAS_INVALID_CONTENT_TYPE"),
    );
  }
}

/**
 * Read request body with a hard max byte limit even when Content-Length is absent.
 */
export async function readBodyWithLimit(
  req: Request,
  maxBytes: number = MAX_BODY_BYTES,
): Promise<Uint8Array> {
  const contentLength = req.headers.get("content-length");
  if (contentLength !== null) {
    const n = Number(contentLength);
    if (Number.isFinite(n) && n > maxBytes) {
      throw new AtlasHttpError(
        413,
        "ATLAS_REQUEST_BODY_TOO_LARGE",
        defaultMessageForCode("ATLAS_REQUEST_BODY_TOO_LARGE"),
      );
    }
  }

  if (!req.body) {
    return new Uint8Array(0);
  }

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // ignore cancel errors
      }
      throw new AtlasHttpError(
        413,
        "ATLAS_REQUEST_BODY_TOO_LARGE",
        defaultMessageForCode("ATLAS_REQUEST_BODY_TOO_LARGE"),
      );
    }
    chunks.push(value);
  }

  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

export interface CheckoutCreateBody {
  company_id: string;
}

/**
 * Parse and validate POST body: only `{ "company_id": "<uuid>" }`.
 * Rejects extra commerce / actor fields.
 */
export function parseCheckoutCreateBody(bytes: Uint8Array): CheckoutCreateBody {
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

  if (text.trim() === "") {
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
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_REQUEST",
      defaultMessageForCode("ATLAS_INVALID_REQUEST"),
    );
  }

  const obj = parsed as Record<string, unknown>;
  const keys = Object.keys(obj);

  for (const key of keys) {
    const lower = key.toLowerCase();
    if (
      (FORBIDDEN_COMMERCE_FIELDS as readonly string[]).includes(lower) ||
      (FORBIDDEN_COMMERCE_FIELDS as readonly string[]).includes(key)
    ) {
      throw new AtlasHttpError(
        400,
        "ATLAS_INVALID_REQUEST",
        "Request contains forbidden commerce fields",
      );
    }
  }

  for (const key of keys) {
    if (key !== "company_id") {
      throw new AtlasHttpError(
        400,
        "ATLAS_INVALID_REQUEST",
        "Request contains unexpected fields",
      );
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
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_REQUEST",
      "company_id must be a UUID",
    );
  }

  return { company_id: companyId.toLowerCase() };
}

export function jsonResponse(
  status: number,
  body: unknown,
  extraHeaders?: HeadersInit,
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  return new Response(JSON.stringify(body), { status, headers });
}

export function jsonErrorResponse(
  status: number,
  errorCode: AtlasErrorCode,
  message: string,
  retryable: boolean,
  correlationId: string,
  extraHeaders?: HeadersInit,
): Response {
  return jsonResponse(
    status,
    atlasErrorBody(errorCode, message, retryable, correlationId),
    extraHeaders,
  );
}

export function assertPostOrOptions(method: string): "OPTIONS" | "POST" {
  const m = method.toUpperCase();
  if (m === "OPTIONS") return "OPTIONS";
  if (m === "POST") return "POST";
  throw new AtlasHttpError(
    405,
    "ATLAS_METHOD_NOT_ALLOWED",
    defaultMessageForCode("ATLAS_METHOD_NOT_ALLOWED"),
  );
}

/** Validate Atlas payment-page checkout URL returned by Paddle / stored on session. */
export function validateAtlasCheckoutUrl(
  checkoutUrl: string,
  paymentPageOrigin: string,
  checkoutPath: string,
  externalTransactionId: string,
): boolean {
  let url: URL;
  try {
    url = new URL(checkoutUrl);
  } catch {
    return false;
  }
  if (url.protocol !== "https:") return false;
  if (url.username !== "" || url.password !== "") return false;
  if (url.hash !== "") return false;
  if (url.origin !== paymentPageOrigin) return false;
  if (url.pathname !== checkoutPath) return false;
  const ptxn = url.searchParams.get("_ptxn");
  if (ptxn !== externalTransactionId) return false;
  return true;
}

export function isHttpsUrl(value: string): boolean {
  try {
    const u = new URL(value);
    return u.protocol === "https:" && u.username === "" && u.password === "";
  } catch {
    return false;
  }
}
