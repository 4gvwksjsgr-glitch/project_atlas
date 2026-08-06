/**
 * Paddle Billing sandbox checkout adapter.
 * Base URL fixed to sandbox; no retries; 10s timeout; injected fetch.
 * Fail-closed status classification; bounded response body reads.
 */

import { validateAtlasCheckoutUrl } from "../../http.ts";
import {
  type BillingProviderCheckoutAdapter,
  PADDLE_API_VERSION,
  PADDLE_DEFINITIVE_CLIENT_STATUSES,
  PADDLE_MAX_RESPONSE_BYTES,
  PADDLE_REQUEST_TIMEOUT_MS,
  PADDLE_SANDBOX_BASE_URL,
  PADDLE_TXN_ID_RE,
  type PaddleCreateCheckoutInput,
  type PaddleCreateCheckoutResult,
  type PaddleTransactionResponse,
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
