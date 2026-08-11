/**
 * billing-webhook-paddle — inbox-only Paddle Sandbox webhook handler.
 * No Premium grant, no company_billing writes, no Paddle API calls.
 */

import {
  atlasErrorBody,
  AtlasHttpError,
  defaultMessageForCode,
} from "../_shared/errors.ts";
import { readBodyWithLimit } from "../_shared/http.ts";
import { logSafe } from "../_shared/logging.ts";
import { sha256HexLower } from "./crypto_hash.ts";
import { parseVerifiedWebhookPayload } from "./payload.ts";
import { verifyPaddleSignature } from "./signature.ts";
import {
  type HandlerDeps,
  WEBHOOK_MAX_BODY_BYTES,
  WEBHOOK_SECRET_ENV,
} from "./types.ts";

function jsonOk(correlationId: string): Response {
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "X-Correlation-Id": correlationId,
    },
  });
}

function jsonErr(
  status: number,
  code: string,
  correlationId: string,
  retryable = false,
): Response {
  return new Response(
    JSON.stringify(
      atlasErrorBody(
        code,
        defaultMessageForCode(code),
        retryable,
        correlationId,
      ),
    ),
    {
      status,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "X-Correlation-Id": correlationId,
        ...(status === 405 ? { Allow: "POST" } : {}),
      },
    },
  );
}

function requireJsonMediaType(contentType: string | null): void {
  if (!contentType) {
    throw new AtlasHttpError(
      415,
      "ATLAS_INVALID_CONTENT_TYPE",
      defaultMessageForCode("ATLAS_INVALID_CONTENT_TYPE"),
    );
  }
  const media = contentType.split(";")[0]!.trim().toLowerCase();
  if (media !== "application/json") {
    throw new AtlasHttpError(
      415,
      "ATLAS_INVALID_CONTENT_TYPE",
      defaultMessageForCode("ATLAS_INVALID_CONTENT_TYPE"),
    );
  }
}

/** Reject oversized Content-Length before secret/body acquisition. */
function rejectOversizedContentLength(req: Request, maxBytes: number): void {
  const contentLength = req.headers.get("content-length");
  if (contentLength === null) return;
  const n = Number(contentLength);
  if (Number.isFinite(n) && n > maxBytes) {
    throw new AtlasHttpError(
      413,
      "ATLAS_REQUEST_BODY_TOO_LARGE",
      defaultMessageForCode("ATLAS_REQUEST_BODY_TOO_LARGE"),
    );
  }
}

function readWebhookSecret(env: HandlerDeps["env"]): string | null {
  const raw = env(WEBHOOK_SECRET_ENV);
  if (raw === undefined || raw === null) return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  return trimmed;
}

export function createHandler(
  deps: HandlerDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const correlationId = deps.uuid();

    try {
      if (req.method !== "POST") {
        return jsonErr(405, "ATLAS_METHOD_NOT_ALLOWED", correlationId);
      }

      // 2. Content-Type + immediately-known body-size limits (before secret).
      requireJsonMediaType(req.headers.get("content-type"));
      rejectOversizedContentLength(req, WEBHOOK_MAX_BODY_BYTES);

      // 3. Secret availability (503 only for otherwise acceptable POST shape).
      const secret = readWebhookSecret(deps.env);
      if (!secret) {
        logSafe("error", "webhook_secret_missing", {
          correlation_id: correlationId,
          event: "secret_missing",
        });
        return jsonErr(503, "ATLAS_WEBHOOK_SECRET_MISSING", correlationId);
      }

      // 4. Bounded raw-body acquisition.
      let rawBody: Uint8Array;
      try {
        rawBody = await readBodyWithLimit(req, WEBHOOK_MAX_BODY_BYTES);
      } catch (err) {
        if (err instanceof AtlasHttpError) {
          return jsonErr(
            err.status,
            err.errorCode,
            correlationId,
            err.retryable,
          );
        }
        throw err;
      }

      const verified = await verifyPaddleSignature({
        header: req.headers.get("paddle-signature") ??
          req.headers.get("Paddle-Signature"),
        rawBody,
        secret,
        nowMs: deps.clock().getTime(),
        subtle: deps.subtle,
      });
      if (!verified.ok) {
        logSafe("warn", "webhook_signature_rejected", {
          correlation_id: correlationId,
          event: "signature_rejected",
          error_code: "ATLAS_WEBHOOK_SIGNATURE_INVALID",
        });
        return jsonErr(401, "ATLAS_WEBHOOK_SIGNATURE_INVALID", correlationId);
      }

      const rawText = new TextDecoder("utf-8", { fatal: false }).decode(
        rawBody,
      );
      const parsed = parseVerifiedWebhookPayload(rawText);
      if (!parsed.ok) {
        return jsonErr(
          400,
          parsed.reason === "invalid_json"
            ? "ATLAS_INVALID_JSON"
            : "ATLAS_INVALID_REQUEST",
          correlationId,
        );
      }

      const payloadHash = await sha256HexLower(rawBody, deps.subtle);

      try {
        const row = await deps.rpc.ingestPaddleSandboxWebhookEventServer({
          external_event_id: parsed.value.event_id,
          event_type: parsed.value.event_type,
          provider_created_at: parsed.value.occurred_at,
          payload_hash: payloadHash,
          payload_json: parsed.value.payload_json,
          classification: parsed.value.classification,
          external_subscription_id: parsed.value.external_subscription_id,
        });

        logSafe("info", "webhook_inbox_ack", {
          correlation_id: correlationId,
          event: "inbox_ack",
          status: 200,
          paddle_kind: parsed.value.classification,
          reused: row.outcome === "duplicate",
        });
        return jsonOk(correlationId);
      } catch (err) {
        if (err instanceof AtlasHttpError) {
          logSafe("error", "webhook_inbox_rpc_failed", {
            correlation_id: correlationId,
            event: "inbox_rpc_failed",
            error_code: err.errorCode,
            status: err.status,
          });
          return jsonErr(
            err.status,
            err.errorCode,
            correlationId,
            err.retryable,
          );
        }
        logSafe("error", "webhook_inbox_rpc_failed", {
          correlation_id: correlationId,
          event: "inbox_rpc_failed",
          error_code: "ATLAS_INTERNAL_ERROR",
          status: 500,
        });
        return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
      }
    } catch (err) {
      if (err instanceof AtlasHttpError) {
        return jsonErr(err.status, err.errorCode, correlationId, err.retryable);
      }
      logSafe("error", "webhook_unhandled_error", {
        correlation_id: correlationId,
        event: "unhandled",
        error_code: "ATLAS_INTERNAL_ERROR",
        status: 500,
      });
      return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
    }
  };
}
