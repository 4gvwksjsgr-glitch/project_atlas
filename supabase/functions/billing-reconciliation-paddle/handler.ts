/**
 * billing-reconciliation-paddle orchestration (D2-B).
 * Injected deps for tests; no real network in unit tests.
 *
 * Flow: JWT → prepare → exact GET subscription → normalize/bind → apply
 * Provider/not-found/invalid → finalizer (after prepare only). Max 1 call each.
 */

import {
  AtlasHttpError,
  defaultMessageForCode,
  httpStatusForAtlasCode,
} from "../_shared/errors.ts";
import { requireAuthenticatedActor } from "../_shared/auth.ts";
import {
  assertPostOrOptions,
  buildOptionsResponse,
  corsHeaders,
  decideCors,
  jsonErrorResponse,
  jsonResponse,
  parseCheckoutCreateBody,
  readBodyWithLimit,
  requireJsonContentType,
  SUCCESS_SCHEMA_VERSION,
} from "../_shared/http.ts";
import { logSafe } from "../_shared/logging.ts";
import {
  readPaddleSandboxApiKey,
  sanitizeProviderMessage,
} from "../_shared/providers/paddle/paddle_adapter.ts";
import type { PaddleGetSubscriptionResult } from "../_shared/providers/paddle/paddle_types.ts";
import {
  assertPrepareProviderBinding,
  normalizePaddleSubscriptionData,
} from "./normalize.ts";
import type {
  HandlerDeps,
  KnownReconciliationOutcome,
  PrepareBillingReconciliationResult,
  ReconciliationFinalizerResult,
  ReconciliationSuccessBody,
} from "./types.ts";
import { KNOWN_RECONCILIATION_OUTCOMES } from "./types.ts";

interface OutcomeHttpMapping {
  status: number;
  errorCode: string;
  retryable: boolean;
}

const OUTCOME_HTTP: Record<
  Exclude<KnownReconciliationOutcome, "updated" | "in_sync">,
  OutcomeHttpMapping
> = {
  busy: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_BUSY",
    retryable: false,
  },
  conflict: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_CONFLICT",
    retryable: false,
  },
  unlinked: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_UNLINKED",
    retryable: false,
  },
  stale_snapshot: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_STALE_SNAPSHOT",
    retryable: false,
  },
  stale_provider_state: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_STALE_PROVIDER_STATE",
    retryable: false,
  },
  catalog_mismatch: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_CATALOG_MISMATCH",
    retryable: false,
  },
  unsupported_state: {
    status: 409,
    errorCode: "ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_STATE",
    retryable: false,
  },
  invalid_provider_response: {
    status: 502,
    errorCode: "ATLAS_BILLING_RECONCILIATION_INVALID_PROVIDER_RESPONSE",
    retryable: false,
  },
  not_found: {
    status: 404,
    errorCode: "ATLAS_BILLING_RECONCILIATION_NOT_FOUND",
    retryable: false,
  },
  provider_error: {
    status: 502,
    errorCode: "ATLAS_BILLING_RECONCILIATION_PROVIDER_ERROR",
    retryable: false,
  },
};

function isKnownOutcome(result: string): result is KnownReconciliationOutcome {
  return (KNOWN_RECONCILIATION_OUTCOMES as readonly string[]).includes(result);
}

function successBody(
  companyId: string,
  result: "updated" | "in_sync",
  providerUpdatedAt: string | null,
): ReconciliationSuccessBody {
  return {
    schema_version: SUCCESS_SCHEMA_VERSION,
    ok: true,
    data: {
      company_id: companyId,
      result,
      provider_updated_at: providerUpdatedAt,
    },
  };
}

/** Map D1 apply/finalizer result to HTTP response. Fail-closed on unknown. */
export function responseForReconciliationOutcome(
  result: string,
  companyId: string,
  providerUpdatedAt: string | null,
  correlationId: string,
  headers: HeadersInit,
): Response {
  if (!isKnownOutcome(result)) {
    return jsonErrorResponse(
      500,
      "ATLAS_INTERNAL_ERROR",
      "Internal error",
      false,
      correlationId,
      headers,
    );
  }

  if (result === "updated" || result === "in_sync") {
    return jsonResponse(
      200,
      successBody(companyId, result, providerUpdatedAt),
      headers,
    );
  }

  const mapped = OUTCOME_HTTP[result];
  return jsonErrorResponse(
    mapped.status,
    mapped.errorCode,
    defaultMessageForCode(mapped.errorCode),
    mapped.retryable,
    correlationId,
    headers,
  );
}

function classifyProviderFailure(
  paddle: PaddleGetSubscriptionResult,
): {
  result: ReconciliationFinalizerResult;
  sanitized: string;
  providerUpdatedAt: string | null;
} | null {
  if (paddle.kind === "success") return null;
  if (paddle.kind === "not_found") {
    return {
      result: "not_found",
      sanitized: sanitizeProviderMessage(
        paddle.sanitized_message,
        "Paddle subscription not found",
      ),
      providerUpdatedAt: null,
    };
  }
  if (paddle.kind === "provider_error") {
    return {
      result: "provider_error",
      sanitized: sanitizeProviderMessage(
        paddle.sanitized_message,
        "Paddle provider error",
      ),
      providerUpdatedAt: null,
    };
  }
  return {
    result: "invalid_provider_response",
    sanitized: sanitizeProviderMessage(
      paddle.sanitized_message,
      "Paddle response invalid",
    ),
    providerUpdatedAt: null,
  };
}

async function finalizeProviderFailure(
  deps: HandlerDeps,
  prepare: PrepareBillingReconciliationResult,
  actorUserId: string,
  failure: {
    result: ReconciliationFinalizerResult;
    sanitized: string;
    providerUpdatedAt: string | null;
  },
  correlationId: string,
  headers: HeadersInit,
): Promise<Response> {
  const recorded = await deps.rpc
    .recordCompanyBillingReconciliationResultServer({
      company_id: prepare.company_id,
      actor_user_id: actorUserId,
      expected_external_subscription_id: prepare.external_subscription_id,
      expected_external_customer_id: prepare.external_customer_id,
      expected_linkage_fingerprint: prepare.expected_linkage_fingerprint,
      result: failure.result,
      error_sanitized: failure.sanitized,
      provider_updated_at: failure.providerUpdatedAt,
    });

  // Prefer server-derived finalizer result (busy|unlinked|stale_snapshot|…).
  return responseForReconciliationOutcome(
    recorded.result,
    recorded.company_id,
    failure.providerUpdatedAt,
    correlationId,
    headers,
  );
}

export async function handleBillingReconciliation(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const correlationId = deps.uuid();
  const method = req.method.toUpperCase();
  const origin = req.headers.get("Origin");

  try {
    assertPostOrOptions(method);
  } catch (err) {
    const headers = corsHeaders(undefined);
    if (err instanceof AtlasHttpError) {
      return jsonErrorResponse(
        err.status,
        err.errorCode,
        err.exposeMessage,
        err.retryable,
        correlationId,
        {
          ...Object.fromEntries(new Headers(headers).entries()),
          Allow: "POST, OPTIONS",
        },
      );
    }
    return jsonErrorResponse(
      405,
      "ATLAS_METHOD_NOT_ALLOWED",
      defaultMessageForCode("ATLAS_METHOD_NOT_ALLOWED"),
      false,
      correlationId,
      headers,
    );
  }

  if (method === "OPTIONS") {
    return buildOptionsResponse(
      origin,
      deps.corsAllowlist,
      correlationId,
    );
  }

  const cors = decideCors(origin, deps.corsAllowlist);
  if (!cors.ok) {
    return jsonErrorResponse(
      403,
      "ATLAS_CORS_ORIGIN_DENIED",
      defaultMessageForCode("ATLAS_CORS_ORIGIN_DENIED"),
      false,
      correlationId,
      corsHeaders(undefined),
    );
  }
  const headers = corsHeaders(cors.allowOrigin);

  try {
    const actor = await requireAuthenticatedActor(
      req.headers.get("Authorization"),
      deps.authLookup,
    );

    if (readPaddleSandboxApiKey(deps.env) === null) {
      throw new AtlasHttpError(
        503,
        "ATLAS_BILLING_RECONCILIATION_UNAVAILABLE",
        defaultMessageForCode("ATLAS_BILLING_RECONCILIATION_UNAVAILABLE"),
        false,
      );
    }

    requireJsonContentType(req.headers.get("Content-Type"));
    const bodyBytes = await readBodyWithLimit(req);
    // Reuse shared strict body parser: only { company_id }; rejects actor/provider fields.
    const body = parseCheckoutCreateBody(bodyBytes);

    const prepare = await deps.rpc.prepareCompanyBillingReconciliationServer({
      company_id: body.company_id,
      actor_user_id: actor.actor_user_id,
    });

    const paddle = await deps.paddle.getSubscription(
      prepare.external_subscription_id,
    );

    const providerFailure = classifyProviderFailure(paddle);
    if (providerFailure) {
      return await finalizeProviderFailure(
        deps,
        prepare,
        actor.actor_user_id,
        providerFailure,
        correlationId,
        headers,
      );
    }

    if (paddle.kind !== "success") {
      // Exhaustiveness guard — should be unreachable.
      throw new AtlasHttpError(
        500,
        "ATLAS_INTERNAL_ERROR",
        "Internal error",
        false,
      );
    }

    const normalized = normalizePaddleSubscriptionData(paddle.data);
    if (!normalized.ok) {
      return await finalizeProviderFailure(
        deps,
        prepare,
        actor.actor_user_id,
        {
          result: "invalid_provider_response",
          sanitized: sanitizeProviderMessage(
            normalized.reason,
            "Paddle snapshot invalid",
          ),
          providerUpdatedAt: null,
        },
        correlationId,
        headers,
      );
    }

    const binding = assertPrepareProviderBinding(prepare, normalized.snapshot);
    if (!binding.ok) {
      return await finalizeProviderFailure(
        deps,
        prepare,
        actor.actor_user_id,
        {
          result: "invalid_provider_response",
          sanitized: sanitizeProviderMessage(
            binding.reason,
            "Paddle snapshot binding mismatch",
          ),
          providerUpdatedAt: null,
        },
        correlationId,
        headers,
      );
    }

    const snap = normalized.snapshot;
    const applied = await deps.rpc.applyCompanyBillingReconciliationServer({
      company_id: prepare.company_id,
      actor_user_id: actor.actor_user_id,
      expected_external_subscription_id: prepare.external_subscription_id,
      expected_external_customer_id: prepare.external_customer_id,
      expected_linkage_fingerprint: prepare.expected_linkage_fingerprint,
      external_price_id: snap.external_price_id,
      provider_subscription_status: snap.provider_subscription_status,
      current_period_start: snap.current_period_start,
      current_period_end: snap.current_period_end,
      cancel_at_period_end: snap.cancel_at_period_end,
      canceled_at: snap.canceled_at,
      provider_updated_at: snap.provider_updated_at,
    });

    return responseForReconciliationOutcome(
      applied.result,
      applied.company_id,
      applied.provider_updated_at,
      correlationId,
      headers,
    );
  } catch (err) {
    if (err instanceof AtlasHttpError) {
      logSafe("warn", "billing_reconciliation_error", {
        correlation_id: correlationId,
        error_code: err.errorCode,
        status: err.status,
      });
      return jsonErrorResponse(
        err.status,
        err.errorCode,
        err.exposeMessage,
        err.retryable,
        correlationId,
        headers,
      );
    }
    logSafe("error", "billing_reconciliation_unexpected", {
      correlation_id: correlationId,
      error_code: "ATLAS_INTERNAL_ERROR",
    });
    return jsonErrorResponse(
      500,
      "ATLAS_INTERNAL_ERROR",
      "Internal error",
      false,
      correlationId,
      headers,
    );
  }
}

export function createHandler(
  deps: HandlerDeps,
): (req: Request) => Promise<Response> {
  return (req) => handleBillingReconciliation(req, deps);
}

export { defaultMessageForCode, httpStatusForAtlasCode };
