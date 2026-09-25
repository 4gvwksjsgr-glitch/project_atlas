/**
 * Paddle Billing sandbox checkout adapter.
 * Base URL fixed to sandbox; no retries; 10s timeout; injected fetch.
 * Fail-closed status classification; bounded response body reads.
 */

import { validateAtlasCheckoutUrl } from "../../http.ts";
import {
  type BillingProviderCheckoutAdapter,
  type BillingProviderSubscriptionReader,
  PADDLE_API_VERSION,
  PADDLE_DEFINITIVE_CLIENT_STATUSES,
  PADDLE_MAX_RESPONSE_BYTES,
  PADDLE_REQUEST_TIMEOUT_MS,
  PADDLE_SANDBOX_BASE_URL,
  PADDLE_SUBSCRIPTION_ID_RE,
  PADDLE_TXN_ID_RE,
  type PaddleCreateCheckoutInput,
  type PaddleCreateCheckoutResult,
  type PaddleGetSubscriptionResult,
  type PaddlePreviewNextBilledAtResult,
  type PaddleSubscriptionData,
  type PaddleSubscriptionPreviewData,
  type PaddleSubscriptionResponse,
  type PaddleTransactionResponse,
  type PaddleUpdateNextBilledAtInput,
  type PaddleUpdateSubscriptionResult,
} from "./paddle_types.ts";

export type EnvReader = (key: string) => string | undefined;

export interface PaddleAdapterDeps {
  fetch: typeof fetch;
  env: EnvReader;
  /** Optional clock for tests; unused by adapter beyond AbortSignal timeout. */
  now?: () => Date;
}

export function isValidPaddleTransactionId(id: string): boolean {
  return PADDLE_TXN_ID_RE.test(id);
}

export function validatePaddleCheckoutUrl(
  checkoutUrl: string,
  paymentPageOrigin: string,
  checkoutPath: string,
  transactionId: string,
): boolean {
  return validateAtlasCheckoutUrl(
    checkoutUrl,
    paymentPageOrigin,
    checkoutPath,
    transactionId,
  );
}

/** Fail-closed whitelist for definitive client rejections. */
export function isDefinitivePaddleClientStatus(status: number): boolean {
  return (PADDLE_DEFINITIVE_CLIENT_STATUSES as readonly number[]).includes(
    status,
  );
}

/**
 * Validate Paddle sandbox API key presence without logging it.
 * Returns trimmed key or null when missing/blank.
 */
export function readPaddleSandboxApiKey(env: EnvReader): string | null {
  const raw = env("PADDLE_SANDBOX_API_KEY");
  if (raw === undefined || raw === null) return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  return trimmed;
}

export function sanitizeProviderMessage(
  raw: unknown,
  fallback: string,
): string {
  if (typeof raw !== "string") return fallback;
  const trimmed = raw.trim().slice(0, 200);
  if (!trimmed) return fallback;
  if (/bearer\s+/i.test(trimmed) || /api[_-]?key/i.test(trimmed)) {
    return fallback;
  }
  return trimmed;
}

/**
 * Read response body with a hard max byte limit even when Content-Length is
 * absent or false. Does not log the body.
 */
export async function readResponseBodyWithLimit(
  response: Response,
  maxBytes: number = PADDLE_MAX_RESPONSE_BYTES,
): Promise<
  | { ok: true; bytes: Uint8Array }
  | { ok: false; reason: "oversized" | "read_failure" }
> {
  const contentLength = response.headers.get("content-length");
  if (contentLength !== null) {
    const n = Number(contentLength);
    if (Number.isFinite(n) && n > maxBytes) {
      try {
        await response.body?.cancel();
      } catch {
        // ignore
      }
      return { ok: false, reason: "oversized" };
    }
  }

  if (!response.body) {
    return { ok: true, bytes: new Uint8Array(0) };
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        try {
          await reader.cancel();
        } catch {
          // ignore
        }
        return { ok: false, reason: "oversized" };
      }
      chunks.push(value);
    }
  } catch {
    try {
      await reader.cancel();
    } catch {
      // ignore
    }
    return { ok: false, reason: "read_failure" };
  }

  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, bytes: out };
}

function uncertain(
  reason:
    | "timeout"
    | "network"
    | "http_5xx"
    | "malformed_response"
    | "invalid_checkout_url"
    | "invalid_transaction_id",
  message: string,
): PaddleCreateCheckoutResult {
  return {
    kind: "uncertain",
    reason,
    sanitized_message: message,
  };
}

export function createPaddleSandboxCheckoutAdapter(
  deps: PaddleAdapterDeps,
): BillingProviderCheckoutAdapter {
  return {
    async createCheckout(
      input: PaddleCreateCheckoutInput,
    ): Promise<PaddleCreateCheckoutResult> {
      const apiKey = readPaddleSandboxApiKey(deps.env);
      if (!apiKey) {
        return uncertain(
          "malformed_response",
          "Paddle sandbox API key not configured",
        );
      }

      const body = {
        items: [
          {
            price_id: input.external_price_id,
            quantity: 1,
          },
        ],
        collection_mode: "automatic",
        checkout: {
          url: input.checkout_page_url,
        },
        custom_data: {
          atlas_schema_version: 1,
          atlas_company_id: input.company_id,
          atlas_checkout_session_id: input.checkout_session_id,
          atlas_offer_code: input.offer_code,
        },
      };

      const controller = new AbortController();
      const timer = setTimeout(
        () => controller.abort(),
        PADDLE_REQUEST_TIMEOUT_MS,
      );

      let response: Response;
      try {
        response = await deps.fetch(
          `${PADDLE_SANDBOX_BASE_URL}/transactions`,
          {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${apiKey}`,
              "Content-Type": "application/json",
              "Paddle-Version": PADDLE_API_VERSION,
            },
            body: JSON.stringify(body),
            signal: controller.signal,
          },
        );
      } catch (err) {
        clearTimeout(timer);
        const aborted = err instanceof Error &&
          (err.name === "AbortError" || /abort/i.test(err.message));
        return uncertain(
          aborted ? "timeout" : "network",
          aborted ? "Paddle request timed out" : "Paddle network error",
        );
      } finally {
        clearTimeout(timer);
      }

      const status = response.status;

      const bodyRead = await readResponseBodyWithLimit(response);
      if (!bodyRead.ok) {
        return uncertain(
          "malformed_response",
          bodyRead.reason === "oversized"
            ? "Paddle response exceeded size limit"
            : "Paddle response body could not be read",
        );
      }

      let json: PaddleTransactionResponse | null = null;
      if (bodyRead.bytes.byteLength > 0) {
        let text: string;
        try {
          text = new TextDecoder("utf-8", { fatal: true }).decode(
            bodyRead.bytes,
          );
        } catch {
          return uncertain(
            "malformed_response",
            "Paddle response was not valid UTF-8",
          );
        }
        try {
          json = JSON.parse(text) as PaddleTransactionResponse;
        } catch {
          if (isDefinitivePaddleClientStatus(status)) {
            return {
              kind: "definitive_client_error",
              http_status: status,
              sanitized_message: "Paddle client error with non-JSON body",
            };
          }
          return uncertain(
            status >= 500 ? "http_5xx" : "malformed_response",
            status >= 500
              ? "Paddle server error"
              : "Paddle response was not JSON",
          );
        }
      }

      if (status >= 500) {
        return uncertain(
          "http_5xx",
          sanitizeProviderMessage(json?.error?.detail, "Paddle server error"),
        );
      }

      if (status >= 400) {
        if (isDefinitivePaddleClientStatus(status)) {
          return {
            kind: "definitive_client_error",
            http_status: status,
            sanitized_message: sanitizeProviderMessage(
              json?.error?.detail,
              "Paddle rejected the request",
            ),
          };
        }
        return uncertain(
          "malformed_response",
          sanitizeProviderMessage(
            json?.error?.detail,
            "Paddle returned a non-definitive client status",
          ),
        );
      }

      if (status < 200 || status >= 300) {
        return uncertain(
          "malformed_response",
          `Unexpected Paddle status ${status}`,
        );
      }

      const txnId = json?.data?.id;
      if (typeof txnId !== "string" || !isValidPaddleTransactionId(txnId)) {
        return uncertain(
          "invalid_transaction_id",
          "Paddle transaction id invalid",
        );
      }

      const checkoutUrl = json?.data?.checkout?.url;
      if (typeof checkoutUrl !== "string") {
        return uncertain(
          "malformed_response",
          "Paddle checkout url missing",
        );
      }

      if (
        !validatePaddleCheckoutUrl(
          checkoutUrl,
          input.payment_page_origin,
          input.checkout_path,
          txnId,
        )
      ) {
        return uncertain(
          "invalid_checkout_url",
          "Paddle checkout url failed validation",
        );
      }

      return {
        kind: "success",
        external_transaction_id: txnId,
        checkout_url: checkoutUrl,
      };
    },
  };
}

/**
 * Exact GET /subscriptions/{id} for sandbox reconciliation.
 * No list/search/customer discovery/transaction fallback. No retries.
 */
export async function getPaddleSandboxSubscription(
  externalSubscriptionId: string,
  deps: PaddleAdapterDeps,
): Promise<PaddleGetSubscriptionResult> {
  const id = externalSubscriptionId.trim();
  if (!id) {
    return {
      kind: "invalid_provider_response",
      sanitized_message: "Subscription id missing",
    };
  }

  const apiKey = readPaddleSandboxApiKey(deps.env);
  if (!apiKey) {
    return {
      kind: "provider_error",
      reason: "http_non_2xx",
      sanitized_message: "Paddle sandbox API key not configured",
    };
  }

  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    PADDLE_REQUEST_TIMEOUT_MS,
  );

  const url = `${PADDLE_SANDBOX_BASE_URL}/subscriptions/${
    encodeURIComponent(id)
  }`;

  let response: Response;
  try {
    response = await deps.fetch(url, {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Paddle-Version": PADDLE_API_VERSION,
      },
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timer);
    const aborted = err instanceof Error &&
      (err.name === "AbortError" || /abort/i.test(err.message));
    return {
      kind: "provider_error",
      reason: aborted ? "timeout" : "network",
      sanitized_message: aborted
        ? "Paddle request timed out"
        : "Paddle network error",
    };
  } finally {
    clearTimeout(timer);
  }

  const status = response.status;

  const bodyRead = await readResponseBodyWithLimit(response);
  if (!bodyRead.ok) {
    const sizeMsg = bodyRead.reason === "oversized"
      ? "Paddle response exceeded size limit"
      : "Paddle response body could not be read";
    if (status === 404) {
      return {
        kind: "not_found",
        sanitized_message: "Paddle subscription not found",
      };
    }
    if (status >= 200 && status < 300) {
      return {
        kind: "invalid_provider_response",
        sanitized_message: sizeMsg,
      };
    }
    return {
      kind: "provider_error",
      reason: status >= 500 ? "http_5xx" : "http_non_2xx",
      sanitized_message: sizeMsg,
    };
  }

  let json: PaddleSubscriptionResponse | null = null;
  if (bodyRead.bytes.byteLength > 0) {
    let text: string;
    try {
      text = new TextDecoder("utf-8", { fatal: true }).decode(bodyRead.bytes);
    } catch {
      if (status === 404) {
        return {
          kind: "not_found",
          sanitized_message: "Paddle subscription not found",
        };
      }
      if (status >= 200 && status < 300) {
        return {
          kind: "invalid_provider_response",
          sanitized_message: "Paddle response was not valid UTF-8",
        };
      }
      return {
        kind: "provider_error",
        reason: status >= 500 ? "http_5xx" : "http_non_2xx",
        sanitized_message: "Paddle response was not valid UTF-8",
      };
    }
    try {
      json = JSON.parse(text) as PaddleSubscriptionResponse;
    } catch {
      if (status === 404) {
        return {
          kind: "not_found",
          sanitized_message: "Paddle subscription not found",
        };
      }
      if (status >= 200 && status < 300) {
        return {
          kind: "invalid_provider_response",
          sanitized_message: "Paddle response was not JSON",
        };
      }
      return {
        kind: "provider_error",
        reason: status >= 500 ? "http_5xx" : "http_non_2xx",
        sanitized_message: "Paddle response was not JSON",
      };
    }
  }

  if (status === 404) {
    return {
      kind: "not_found",
      sanitized_message: sanitizeProviderMessage(
        json?.error?.detail,
        "Paddle subscription not found",
      ),
    };
  }

  if (status >= 500) {
    return {
      kind: "provider_error",
      reason: "http_5xx",
      sanitized_message: sanitizeProviderMessage(
        json?.error?.detail,
        "Paddle server error",
      ),
    };
  }

  if (status < 200 || status >= 300) {
    return {
      kind: "provider_error",
      reason: "http_non_2xx",
      sanitized_message: sanitizeProviderMessage(
        json?.error?.detail,
        `Paddle returned status ${status}`,
      ),
    };
  }

  // 2xx: require structural envelope with object `data`
  if (
    json === null ||
    json.data === null ||
    json.data === undefined ||
    typeof json.data !== "object" ||
    Array.isArray(json.data)
  ) {
    return {
      kind: "invalid_provider_response",
      sanitized_message: "Paddle subscription envelope missing data",
    };
  }

  return {
    kind: "success",
    data: json.data,
  };
}

export function createPaddleSandboxSubscriptionReader(
  deps: PaddleAdapterDeps,
): BillingProviderSubscriptionReader {
  return {
    getSubscription(externalSubscriptionId: string) {
      return getPaddleSandboxSubscription(externalSubscriptionId, deps);
    },
  };
}

// ---------------------------------------------------------------------------
// PATCH /subscriptions/{id} and /subscriptions/{id}/preview — next_billed_at
// ---------------------------------------------------------------------------

const RFC3339_UTC_RE = /^(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/;

/** Strict RFC3339 UTC ("Z") timestamp that round-trips to the same date. */
export function isRfc3339UtcTimestamp(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const m = RFC3339_UTC_RE.exec(value);
  if (!m) return false;
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return false;
  return new Date(ms).toISOString().slice(0, 10) === m[1];
}

function sameInstant(a: unknown, b: string): boolean {
  if (typeof a !== "string") return false;
  const ma = Date.parse(a);
  const mb = Date.parse(b);
  return !Number.isNaN(ma) && !Number.isNaN(mb) && ma === mb;
}

type PatchUncertainReason =
  | "timeout"
  | "network"
  | "http_5xx"
  | "malformed_response";

type PatchOutcome<T> =
  | { kind: "ok"; data: T }
  | {
    kind: "definitive_client_error";
    http_status: number;
    sanitized_message: string;
    paddle_error_code: string | null;
  }
  | {
    kind: "uncertain";
    reason: PatchUncertainReason;
    sanitized_message: string;
  };

function localRejection<T>(message: string): PatchOutcome<T> {
  return {
    kind: "definitive_client_error",
    http_status: 0,
    sanitized_message: message,
    paddle_error_code: null,
  };
}

function sanitizePaddleErrorCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  return /^[a-z0-9_.-]{1,100}$/i.test(trimmed) ? trimmed : null;
}

/**
 * Sends the exact minimal next_billed_at PATCH body. No retries, no
 * idempotency header. Classification mirrors createCheckout.
 */
async function sendNextBilledAtPatch<T extends PaddleSubscriptionData>(
  input: PaddleUpdateNextBilledAtInput,
  deps: PaddleAdapterDeps,
  preview: boolean,
): Promise<PatchOutcome<T>> {
  const id = typeof input.external_subscription_id === "string"
    ? input.external_subscription_id.trim()
    : "";
  if (!PADDLE_SUBSCRIPTION_ID_RE.test(id)) {
    return localRejection("Subscription id invalid (request not sent)");
  }
  if (!isRfc3339UtcTimestamp(input.next_billed_at)) {
    return localRejection("next_billed_at invalid (request not sent)");
  }
  if (input.proration_billing_mode !== "do_not_bill") {
    return localRejection(
      "proration_billing_mode must be do_not_bill (request not sent)",
    );
  }

  const apiKey = readPaddleSandboxApiKey(deps.env);
  if (!apiKey) {
    return localRejection(
      "Paddle sandbox API key not configured (request not sent)",
    );
  }

  const body = {
    next_billed_at: input.next_billed_at,
    proration_billing_mode: "do_not_bill",
  };

  const url = `${PADDLE_SANDBOX_BASE_URL}/subscriptions/${
    encodeURIComponent(id)
  }${preview ? "/preview" : ""}`;

  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    PADDLE_REQUEST_TIMEOUT_MS,
  );

  let response: Response;
  try {
    response = await deps.fetch(url, {
      method: "PATCH",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "Paddle-Version": PADDLE_API_VERSION,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timer);
    const aborted = err instanceof Error &&
      (err.name === "AbortError" || /abort/i.test(err.message));
    return {
      kind: "uncertain",
      reason: aborted ? "timeout" : "network",
      sanitized_message: aborted
        ? "Paddle request timed out"
        : "Paddle network error",
    };
  } finally {
    clearTimeout(timer);
  }

  const status = response.status;

  const bodyRead = await readResponseBodyWithLimit(response);
  if (!bodyRead.ok) {
    return {
      kind: "uncertain",
      reason: status >= 500 ? "http_5xx" : "malformed_response",
      sanitized_message: bodyRead.reason === "oversized"
        ? "Paddle response exceeded size limit"
        : "Paddle response body could not be read",
    };
  }

  type Envelope = {
    data?: T | null;
    error?: { detail?: unknown; code?: unknown } | null;
  };
  let json: Envelope | null = null;
  if (bodyRead.bytes.byteLength > 0) {
    let parsed: unknown;
    try {
      const text = new TextDecoder("utf-8", { fatal: true }).decode(
        bodyRead.bytes,
      );
      parsed = JSON.parse(text);
    } catch {
      if (isDefinitivePaddleClientStatus(status)) {
        return {
          kind: "definitive_client_error",
          http_status: status,
          sanitized_message: "Paddle client error with non-JSON body",
          paddle_error_code: null,
        };
      }
      return {
        kind: "uncertain",
        reason: status >= 500 ? "http_5xx" : "malformed_response",
        sanitized_message: status >= 500
          ? "Paddle server error"
          : "Paddle response was not JSON",
      };
    }
    if (parsed !== null && typeof parsed === "object") {
      json = parsed as Envelope;
    }
  }

  if (status >= 500) {
    return {
      kind: "uncertain",
      reason: "http_5xx",
      sanitized_message: sanitizeProviderMessage(
        json?.error?.detail,
        "Paddle server error",
      ),
    };
  }

  if (status >= 400) {
    if (isDefinitivePaddleClientStatus(status)) {
      return {
        kind: "definitive_client_error",
        http_status: status,
        sanitized_message: sanitizeProviderMessage(
          json?.error?.detail,
          "Paddle rejected the request",
        ),
        paddle_error_code: sanitizePaddleErrorCode(json?.error?.code),
      };
    }
    return {
      kind: "uncertain",
      reason: "malformed_response",
      sanitized_message: sanitizeProviderMessage(
        json?.error?.detail,
        "Paddle returned a non-definitive client status",
      ),
    };
  }

  if (status < 200 || status >= 300) {
    return {
      kind: "uncertain",
      reason: "malformed_response",
      sanitized_message: `Unexpected Paddle status ${status}`,
    };
  }

  const data = json?.data;
  if (
    data === null || data === undefined || typeof data !== "object" ||
    Array.isArray(data)
  ) {
    return {
      kind: "uncertain",
      reason: "malformed_response",
      sanitized_message: "Paddle subscription envelope missing data",
    };
  }

  if (typeof data.id === "string" && data.id !== id) {
    return {
      kind: "uncertain",
      reason: "malformed_response",
      sanitized_message: "Paddle subscription id mismatch",
    };
  }

  return { kind: "ok", data };
}

/** Paddle amounts are integer strings in the lowest currency denomination. */
function parseMinorAmount(raw: unknown): bigint | null {
  if (typeof raw !== "string" || !/^-?\d{1,30}$/.test(raw.trim())) {
    return null;
  }
  return BigInt(raw.trim());
}

/**
 * Classifies a preview response. Any missing/unparseable monetary field on a
 * present object is treated as unsafe (fail-closed).
 */
export function classifyNextBilledAtPreview(
  data: PaddleSubscriptionPreviewData,
  requestedNextBilledAt: string,
): PaddlePreviewNextBilledAtResult {
  const immediate = data.immediate_transaction;
  if (immediate !== null && immediate !== undefined) {
    if (typeof immediate !== "object" || Array.isArray(immediate)) {
      return {
        kind: "unsafe_unexpected",
        sanitized_message: "Preview immediate_transaction malformed",
      };
    }
    const totals = immediate.details?.totals;
    const grandTotalRaw = totals?.grand_total ?? null;
    const grandTotal = parseMinorAmount(grandTotalRaw);
    const total = parseMinorAmount(totals?.total);
    if (grandTotal !== null && grandTotal > 0n) {
      return {
        kind: "unsafe_immediate_charge",
        sanitized_message: "Preview reports an immediate charge",
        immediate_grand_total: typeof grandTotalRaw === "string"
          ? grandTotalRaw
          : null,
      };
    }
    if (total !== null && total > 0n) {
      return {
        kind: "unsafe_immediate_charge",
        sanitized_message: "Preview reports an immediate charge",
        immediate_grand_total: typeof grandTotalRaw === "string"
          ? grandTotalRaw
          : null,
      };
    }
    const totalPresent = totals?.total !== null && totals?.total !== undefined;
    if (grandTotal !== 0n || (totalPresent && total !== 0n)) {
      return {
        kind: "unsafe_unexpected",
        sanitized_message: "Preview immediate_transaction totals not zero",
      };
    }
  }

  const summary = data.update_summary;
  if (summary !== null && summary !== undefined) {
    if (typeof summary !== "object" || Array.isArray(summary)) {
      return {
        kind: "unsafe_unexpected",
        sanitized_message: "Preview update_summary malformed",
      };
    }
    const charge = summary.charge;
    if (charge !== null && charge !== undefined) {
      const amount = parseMinorAmount(charge.amount);
      if (amount === null) {
        return {
          kind: "unsafe_unexpected",
          sanitized_message: "Preview update_summary charge malformed",
        };
      }
      if (amount > 0n) {
        return {
          kind: "unsafe_immediate_charge",
          sanitized_message: "Preview update_summary reports a charge",
          immediate_grand_total: null,
        };
      }
    }
    const result = summary.result;
    if (result !== null && result !== undefined && result.action === "charge") {
      const amount = parseMinorAmount(result.amount);
      if (amount === null || amount !== 0n) {
        return {
          kind: "unsafe_immediate_charge",
          sanitized_message: "Preview update_summary result is a charge",
          immediate_grand_total: null,
        };
      }
    }
  }

  const previewNext = data.next_billed_at;
  if (typeof previewNext !== "string" || !isRfc3339UtcTimestamp(previewNext)) {
    return {
      kind: "unsafe_unexpected",
      sanitized_message: "Preview next_billed_at missing or invalid",
    };
  }
  if (!sameInstant(previewNext, requestedNextBilledAt)) {
    return {
      kind: "unsafe_unexpected",
      sanitized_message: "Preview next_billed_at does not match request",
    };
  }

  return { kind: "safe", data, preview_next_billed_at: previewNext };
}

/**
 * PATCH /subscriptions/{id}/preview with exactly
 * { next_billed_at, proration_billing_mode: "do_not_bill" }. Fail-closed.
 */
export async function previewPaddleSandboxSubscriptionNextBilledAt(
  input: PaddleUpdateNextBilledAtInput,
  deps: PaddleAdapterDeps,
): Promise<PaddlePreviewNextBilledAtResult> {
  const outcome = await sendNextBilledAtPatch<PaddleSubscriptionPreviewData>(
    input,
    deps,
    true,
  );
  if (outcome.kind !== "ok") return outcome;
  return classifyNextBilledAtPreview(outcome.data, input.next_billed_at);
}

/**
 * PATCH /subscriptions/{id} with exactly
 * { next_billed_at, proration_billing_mode: "do_not_bill" }.
 * No retries, no idempotency header; caller verifies the returned
 * next_billed_at (and may re-GET) before finalizing.
 */
export async function updatePaddleSandboxSubscriptionNextBilledAt(
  input: PaddleUpdateNextBilledAtInput,
  deps: PaddleAdapterDeps,
): Promise<PaddleUpdateSubscriptionResult> {
  const outcome = await sendNextBilledAtPatch<PaddleSubscriptionData>(
    input,
    deps,
    false,
  );
  if (outcome.kind !== "ok") return outcome;
  const data = outcome.data;
  const nextBilledAt = typeof data.next_billed_at === "string"
    ? data.next_billed_at
    : null;
  const endsAt = data.current_billing_period?.ends_at;
  return {
    kind: "success",
    data,
    next_billed_at: nextBilledAt,
    current_period_ends_at: typeof endsAt === "string" ? endsAt : null,
  };
}
