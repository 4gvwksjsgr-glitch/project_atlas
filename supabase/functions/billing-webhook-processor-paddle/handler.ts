/**
 * billing-webhook-processor-paddle — claim_next → apply → fail orchestrator.
 * No ingest, no Paddle API, no checkout, no arbitrary inbox IDs.
 */

import {
  atlasErrorBody,
  AtlasHttpError,
  defaultMessageForCode,
} from "../_shared/errors.ts";
import { readBodyWithLimit } from "../_shared/http.ts";
import { logSafe } from "../_shared/logging.ts";
import { isTerminalApplyOutcome, sanitizeApplyFailure } from "./sanitize.ts";
import { timingSafeEqualString } from "./secret.ts";
import {
  type ApplyRow,
  type FailRow,
  type HandlerDeps,
  PROCESSOR_INTERNAL_ERROR,
  PROCESSOR_INVOKE_HEADER,
  PROCESSOR_INVOKE_SECRET_ENV,
  PROCESSOR_MAX_BODY_BYTES,
  type ProcessorSuccessBody,
  TERMINAL_APPLY_STATUS_BY_OUTCOME,
  type TerminalApplyOutcome,
} from "./types.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function jsonOk(body: ProcessorSuccessBody): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "X-Correlation-Id": body.correlation_id,
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

function internalError(): AtlasHttpError {
  return new AtlasHttpError(
    500,
    "ATLAS_INTERNAL_ERROR",
    defaultMessageForCode("ATLAS_INTERNAL_ERROR"),
  );
}

function readInvokeSecret(env: HandlerDeps["env"]): string | null {
  const raw = env(PROCESSOR_INVOKE_SECRET_ENV);
  if (raw === undefined || raw === null) return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  return trimmed;
}

async function assertInvokeAuthorized(
  req: Request,
  expected: string,
  subtle: SubtleCrypto,
): Promise<void> {
  const provided = req.headers.get(PROCESSOR_INVOKE_HEADER);
  if (provided === null || provided.trim().length === 0) {
    throw new AtlasHttpError(
      401,
      "ATLAS_NOT_AUTHENTICATED",
      defaultMessageForCode("ATLAS_NOT_AUTHENTICATED"),
    );
  }
  const ok = await timingSafeEqualString(provided, expected, subtle);
  if (!ok) {
    throw new AtlasHttpError(
      401,
      "ATLAS_NOT_AUTHENTICATED",
      defaultMessageForCode("ATLAS_NOT_AUTHENTICATED"),
    );
  }
}

/**
 * Accept only empty body or `{}`. Reject any supplied processing target fields.
 */
async function assertEmptyProcessorBody(req: Request): Promise<void> {
  const contentType = req.headers.get("content-type");
  const raw = await readBodyWithLimit(req, PROCESSOR_MAX_BODY_BYTES);
  const text = new TextDecoder().decode(raw).trim();

  if (text.length === 0) {
    return;
  }

  if (contentType) {
    const media = contentType.split(";")[0]!.trim().toLowerCase();
    if (media !== "application/json") {
      throw new AtlasHttpError(
        415,
        "ATLAS_INVALID_CONTENT_TYPE",
        defaultMessageForCode("ATLAS_INVALID_CONTENT_TYPE"),
      );
    }
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

  if (
    parsed === null ||
    typeof parsed !== "object" ||
    Array.isArray(parsed)
  ) {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_REQUEST",
      defaultMessageForCode("ATLAS_INVALID_REQUEST"),
    );
  }

  if (Object.keys(parsed as Record<string, unknown>).length !== 0) {
    throw new AtlasHttpError(
      400,
      "ATLAS_INVALID_REQUEST",
      defaultMessageForCode("ATLAS_INVALID_REQUEST"),
    );
  }
}

function assertClaimReady(row: {
  outcome: string;
  inbox_event_id: string | null;
  processing_status: string | null;
  attempt_count: number | null;
}): { inboxEventId: string; attemptCount: number } {
  const id = row.inbox_event_id;
  if (typeof id !== "string" || !UUID_RE.test(id)) {
    throw internalError();
  }
  if (row.processing_status !== "processing") {
    throw internalError();
  }
  if (
    typeof row.attempt_count !== "number" ||
    !Number.isInteger(row.attempt_count) ||
    row.attempt_count < 1
  ) {
    throw internalError();
  }
  return { inboxEventId: id, attemptCount: row.attempt_count };
}

function isValidAttemptCount(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 1;
}

/**
 * Validate non-exception apply row shape + claimed-UUID / attempt equality.
 * Does NOT decide terminal vs unexpected — caller does.
 */
function parseApplyRow(
  row: ApplyRow,
  claimedInboxId: string,
  claimedAttempt: number,
): {
  outcome: string;
  inboxEventId: string;
  processingStatus: string;
  attemptCount: number;
} {
  if (typeof row.outcome !== "string" || row.outcome.length === 0) {
    throw internalError();
  }
  const id = row.inbox_event_id;
  if (typeof id !== "string" || !UUID_RE.test(id) || id !== claimedInboxId) {
    throw internalError();
  }
  if (typeof row.processing_status !== "string") {
    throw internalError();
  }
  if (!isValidAttemptCount(row.attempt_count)) {
    throw internalError();
  }
  // Apply does not increment attempt_count — must match claim.
  if (row.attempt_count !== claimedAttempt) {
    throw internalError();
  }
  return {
    outcome: row.outcome,
    inboxEventId: id,
    processingStatus: row.processing_status,
    attemptCount: row.attempt_count,
  };
}

function assertTerminalApplyState(
  outcome: TerminalApplyOutcome,
  processingStatus: string,
): void {
  const expected = TERMINAL_APPLY_STATUS_BY_OUTCOME[outcome];
  if (processingStatus !== expected) {
    throw internalError();
  }
}

/**
 * Validate fail-finalizer success: outcome/status failed, same UUID, attempt match.
 */
function assertFailFinalized(
  row: FailRow,
  claimedInboxId: string,
  claimedAttempt: number,
): void {
  if (row.outcome !== "failed") {
    throw internalError();
  }
  const id = row.inbox_event_id;
  if (typeof id !== "string" || !UUID_RE.test(id) || id !== claimedInboxId) {
    throw internalError();
  }
  if (row.processing_status !== "failed") {
    throw internalError();
  }
  if (!isValidAttemptCount(row.attempt_count)) {
    throw internalError();
  }
  // Fail finalizer does not increment attempt_count — must match claim.
  if (row.attempt_count !== claimedAttempt) {
    throw internalError();
  }
}

export function createHandler(
  deps: HandlerDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const correlationId = deps.uuid();
    const started = deps.clock().getTime();
    const subtle = deps.subtle ?? crypto.subtle;

    try {
      if (req.method !== "POST") {
        return jsonErr(405, "ATLAS_METHOD_NOT_ALLOWED", correlationId);
      }

      const expectedSecret = readInvokeSecret(deps.env);
      if (!expectedSecret) {
        logSafe("error", "processor_invoke_secret_missing", {
          correlation_id: correlationId,
          event: "secret_missing",
        });
        return jsonErr(503, "ATLAS_INTERNAL_ERROR", correlationId);
      }

      await assertInvokeAuthorized(req, expectedSecret, subtle);
      await assertEmptyProcessorBody(req);

      // TX1 — claim_next (SQL kill switch authoritative)
      const claim = await deps.rpc.claimNextPaddleSandboxWebhookEventServer();

      if (claim.outcome === "disabled" || claim.outcome === "empty") {
        logSafe("info", "processor_no_work", {
          correlation_id: correlationId,
          event: "no_work",
          claim_outcome: claim.outcome,
          duration_ms: deps.clock().getTime() - started,
        });
        return jsonOk({
          ok: true,
          outcome: claim.outcome,
          correlation_id: correlationId,
        });
      }

      if (claim.outcome !== "claimed" && claim.outcome !== "reclaimed") {
        logSafe("error", "processor_unexpected_claim_outcome", {
          correlation_id: correlationId,
          event: "unexpected_claim",
          claim_outcome: claim.outcome,
        });
        return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
      }

      const ready = assertClaimReady(claim);

      logSafe("info", "processor_claimed", {
        correlation_id: correlationId,
        event: "claimed",
        claim_outcome: claim.outcome,
        inbox_event_id: ready.inboxEventId,
        attempt_count: ready.attemptCount,
      });

      // TX2 — apply exactly once
      let appliedRaw: ApplyRow;
      try {
        appliedRaw = await deps.rpc.applyPaddleSandboxWebhookEventServer(
          ready.inboxEventId,
        );
      } catch (applyErr) {
        const sanitized = sanitizeApplyFailure(applyErr);
        logSafe("warn", "processor_apply_failed", {
          correlation_id: correlationId,
          event: "apply_failed",
          inbox_event_id: ready.inboxEventId,
          attempt_count: ready.attemptCount,
          error_code: sanitized,
        });

        // TX3 — fail finalizer exactly once, then validate result
        let failRow: FailRow;
        try {
          failRow = await deps.rpc
            .failPaddleSandboxWebhookEventProcessingServer(
              ready.inboxEventId,
              sanitized,
            );
        } catch {
          logSafe("error", "processor_fail_finalizer_failed", {
            correlation_id: correlationId,
            event: "fail_finalizer_failed",
            inbox_event_id: ready.inboxEventId,
            error_code: sanitized,
            duration_ms: deps.clock().getTime() - started,
          });
          return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
        }

        try {
          assertFailFinalized(
            failRow,
            ready.inboxEventId,
            ready.attemptCount,
          );
        } catch {
          logSafe("error", "processor_fail_finalizer_unexpected", {
            correlation_id: correlationId,
            event: "fail_finalizer_unexpected",
            inbox_event_id: ready.inboxEventId,
            fail_outcome: typeof failRow.outcome === "string"
              ? failRow.outcome
              : "invalid",
            duration_ms: deps.clock().getTime() - started,
          });
          return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
        }

        logSafe("info", "processor_failed_finalized", {
          correlation_id: correlationId,
          event: "failed_finalized",
          inbox_event_id: ready.inboxEventId,
          attempt_count: ready.attemptCount,
          error_code: sanitized,
          duration_ms: deps.clock().getTime() - started,
        });

        return jsonOk({
          ok: true,
          outcome: "failed_finalized",
          correlation_id: correlationId,
          inbox_event_id: ready.inboxEventId,
          attempt_count: ready.attemptCount,
          error_code: sanitized,
        });
      }

      let applied;
      try {
        applied = parseApplyRow(
          appliedRaw,
          ready.inboxEventId,
          ready.attemptCount,
        );
      } catch {
        logSafe("error", "processor_apply_result_invalid", {
          correlation_id: correlationId,
          event: "apply_result_invalid",
          inbox_event_id: ready.inboxEventId,
          duration_ms: deps.clock().getTime() - started,
        });
        // Malformed apply object: do NOT fail-finalize (state unknown).
        return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
      }

      if (isTerminalApplyOutcome(applied.outcome)) {
        try {
          assertTerminalApplyState(
            applied.outcome,
            applied.processingStatus,
          );
        } catch {
          logSafe("error", "processor_apply_terminal_status_mismatch", {
            correlation_id: correlationId,
            event: "apply_terminal_status_mismatch",
            inbox_event_id: ready.inboxEventId,
            apply_outcome: applied.outcome,
            duration_ms: deps.clock().getTime() - started,
          });
          return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
        }

        logSafe("info", "processor_processed", {
          correlation_id: correlationId,
          event: "processed",
          inbox_event_id: ready.inboxEventId,
          attempt_count: ready.attemptCount,
          apply_outcome: applied.outcome,
          duration_ms: deps.clock().getTime() - started,
        });
        return jsonOk({
          ok: true,
          outcome: "processed",
          correlation_id: correlationId,
          inbox_event_id: ready.inboxEventId,
          attempt_count: ready.attemptCount,
          apply_outcome: applied.outcome,
        });
      }

      // Unexpected outcome with valid shape + matching UUID.
      logSafe("error", "processor_unexpected_apply_outcome", {
        correlation_id: correlationId,
        event: "unexpected_apply",
        inbox_event_id: ready.inboxEventId,
        apply_outcome: applied.outcome,
      });

      if (applied.processingStatus !== "processing") {
        // Already terminal/non-processing — do not rewrite via fail-finalizer.
        return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
      }

      let failRow: FailRow;
      try {
        failRow = await deps.rpc.failPaddleSandboxWebhookEventProcessingServer(
          ready.inboxEventId,
          PROCESSOR_INTERNAL_ERROR,
        );
      } catch {
        logSafe("error", "processor_fail_finalizer_failed", {
          correlation_id: correlationId,
          event: "fail_finalizer_failed",
          inbox_event_id: ready.inboxEventId,
          error_code: PROCESSOR_INTERNAL_ERROR,
          duration_ms: deps.clock().getTime() - started,
        });
        return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
      }

      try {
        assertFailFinalized(failRow, ready.inboxEventId, ready.attemptCount);
      } catch {
        logSafe("error", "processor_fail_finalizer_unexpected", {
          correlation_id: correlationId,
          event: "fail_finalizer_unexpected",
          inbox_event_id: ready.inboxEventId,
          fail_outcome: typeof failRow.outcome === "string"
            ? failRow.outcome
            : "invalid",
          duration_ms: deps.clock().getTime() - started,
        });
        return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
      }

      return jsonOk({
        ok: true,
        outcome: "failed_finalized",
        correlation_id: correlationId,
        inbox_event_id: ready.inboxEventId,
        attempt_count: ready.attemptCount,
        error_code: PROCESSOR_INTERNAL_ERROR,
      });
    } catch (err) {
      if (err instanceof AtlasHttpError) {
        if (
          err.status === 401 ||
          err.status === 400 ||
          err.status === 405 ||
          err.status === 413 ||
          err.status === 415
        ) {
          return jsonErr(
            err.status,
            err.errorCode,
            correlationId,
            err.retryable,
          );
        }
        if (err.status === 500 && err.errorCode === "ATLAS_INTERNAL_ERROR") {
          return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
        }
      }
      logSafe("error", "processor_handler_error", {
        correlation_id: correlationId,
        event: "handler_error",
        duration_ms: deps.clock().getTime() - started,
      });
      return jsonErr(500, "ATLAS_INTERNAL_ERROR", correlationId);
    }
  };
}
