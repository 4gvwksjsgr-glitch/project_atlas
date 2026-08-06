/**
 * billing-checkout-create orchestration.
 * Injected deps for tests; no real network in unit tests.
 */

import {
  AtlasHttpError,
  defaultMessageForCode,
  httpStatusForAtlasCode,
  retryableForAtlasCode,
} from "../_shared/errors.ts";
import { requireAuthenticatedActor } from "../_shared/auth.ts";
import {
  assertPostOrOptions,
  buildOptionsResponse,
  corsHeaders,
  decideCors,
  isHttpsUrl,
  jsonErrorResponse,
  jsonResponse,
  parseCheckoutCreateBody,
  readBodyWithLimit,
  requireIdempotencyKey,
  requireJsonContentType,
  SUCCESS_SCHEMA_VERSION,
  validateAtlasCheckoutUrl,
} from "../_shared/http.ts";
import { logSafe } from "../_shared/logging.ts";
import { readPaddleSandboxApiKey } from "../_shared/providers/paddle/paddle_adapter.ts";
import type {
  CheckoutCreateSuccessBody,
  HandlerDeps,
  ReserveBillingCheckoutSessionRow,
} from "./types.ts";
import {
  EXPECTED_PROVIDER_CODE,
  EXPECTED_PROVIDER_ENVIRONMENT,
  OFFER_CODE,
} from "./types.ts";

function successBody(
  reservation: ReserveBillingCheckoutSessionRow,
  checkoutUrl: string,
  reused: boolean,
): CheckoutCreateSuccessBody {
  return {
    schema_version: SUCCESS_SCHEMA_VERSION,
    checkout_session_id: reservation.session_id,
    checkout_url: checkoutUrl,
    return_token: reservation.return_token_plain,
    return_token_version: reservation.return_token_version,
    expires_at: reservation.expires_at,
    reused,
  };
}

function providerRejectedResponse(
  correlationId: string,
  headers: HeadersInit,
): Response {
  return jsonErrorResponse(
    502,
    "ATLAS_PROVIDER_REQUEST_REJECTED",
    defaultMessageForCode("ATLAS_PROVIDER_REQUEST_REJECTED"),
    false,
    correlationId,
    headers,
  );
}

/** Validate reserve outputs required before any provider call. */
export function validateReservationRuntime(
  reservation: ReserveBillingCheckoutSessionRow,
): void {
  if (reservation.provider_code !== EXPECTED_PROVIDER_CODE) {
    throw new AtlasHttpError(
      409,
      "ATLAS_CHECKOUT_UNAVAILABLE",
      defaultMessageForCode("ATLAS_CHECKOUT_UNAVAILABLE"),
    );
  }
  if (reservation.provider_environment !== EXPECTED_PROVIDER_ENVIRONMENT) {
    throw new AtlasHttpError(
      409,
      "ATLAS_CHECKOUT_UNAVAILABLE",
      defaultMessageForCode("ATLAS_CHECKOUT_UNAVAILABLE"),
    );
  }
  if (
    typeof reservation.external_price_id !== "string" ||
    reservation.external_price_id.trim() === ""
  ) {
    throw new AtlasHttpError(
      409,
      "ATLAS_CHECKOUT_UNAVAILABLE",
      defaultMessageForCode("ATLAS_CHECKOUT_UNAVAILABLE"),
    );
  }
  if (
    typeof reservation.checkout_page_url !== "string" ||
    !isHttpsUrl(reservation.checkout_page_url)
  ) {
    throw new AtlasHttpError(
      409,
      "ATLAS_CHECKOUT_UNAVAILABLE",
      defaultMessageForCode("ATLAS_CHECKOUT_UNAVAILABLE"),
    );
  }
}

function outcomeUnknownResponse(
  correlationId: string,
  headers: HeadersInit,
): Response {
  return jsonErrorResponse(
    409,
    "ATLAS_PROVIDER_OUTCOME_UNKNOWN",
    defaultMessageForCode("ATLAS_PROVIDER_OUTCOME_UNKNOWN"),
    false,
    correlationId,
    headers,
  );
}

function inProgressResponse(
  correlationId: string,
  headers: HeadersInit,
): Response {
  return jsonErrorResponse(
    409,
    "ATLAS_CHECKOUT_IN_PROGRESS",
    defaultMessageForCode("ATLAS_CHECKOUT_IN_PROGRESS"),
    true,
    correlationId,
    headers,
  );
}

function handleCreatedState(
  reservation: ReserveBillingCheckoutSessionRow,
  correlationId: string,
  headers: HeadersInit,
): Response {
  const txnId = reservation.existing_external_transaction_id;
  const url = reservation.existing_checkout_url;
  if (
    !txnId || !url ||
    !validateAtlasCheckoutUrl(
      url,
      reservation.payment_page_origin,
      reservation.checkout_path,
      txnId,
    )
  ) {
    throw new AtlasHttpError(
      409,
      "ATLAS_CHECKOUT_UNAVAILABLE",
      defaultMessageForCode("ATLAS_CHECKOUT_UNAVAILABLE"),
    );
  }
  logSafe("info", "checkout_reused_created", {
    correlation_id: correlationId,
    checkout_session_id: reservation.session_id,
    provider_create_status: reservation.provider_create_status,
    reused: true,
  });
  return jsonResponse(200, successBody(reservation, url, true), headers);
}

/**
 * Map provider_create_status after a CAS race on definitive Paddle failure.
 * Never calls Paddle. Failed → definitive reject; unexpected → outcome_unknown.
 */
export function mapAfterDefinitiveFailureRace(
  reservation: ReserveBillingCheckoutSessionRow,
  correlationId: string,
  headers: HeadersInit,
): Response {
  const status = reservation.provider_create_status;
  if (status === "created") {
    const txnId = reservation.existing_external_transaction_id;
    const url = reservation.existing_checkout_url;
    if (
      txnId && url &&
      validateAtlasCheckoutUrl(
        url,
        reservation.payment_page_origin,
        reservation.checkout_path,
        txnId,
      )
    ) {
      logSafe("info", "checkout_reused_created_after_failed_race", {
        correlation_id: correlationId,
        checkout_session_id: reservation.session_id,
        provider_create_status: "created",
        reused: true,
      });
      return jsonResponse(200, successBody(reservation, url, true), headers);
    }
    // Contradictory created shape → cannot prove safe reuse.
    return outcomeUnknownResponse(correlationId, headers);
  }
  if (status === "processing") {
    return inProgressResponse(correlationId, headers);
  }
  if (status === "outcome_unknown") {
    return outcomeUnknownResponse(correlationId, headers);
  }
  if (status === "failed") {
    return providerRejectedResponse(correlationId, headers);
  }
  return outcomeUnknownResponse(correlationId, headers);
}

/**
 * Map provider_create_status to response / next action.
 * Returns Response for terminal states, or "not_started" to continue.
 */
export function mapReservationState(
  reservation: ReserveBillingCheckoutSessionRow,
  correlationId: string,
  headers: HeadersInit,
): Response | "not_started" {
  const status = reservation.provider_create_status;
  if (status === "created") {
    return handleCreatedState(reservation, correlationId, headers);
  }
  if (status === "processing") {
    return inProgressResponse(correlationId, headers);
  }
  if (status === "outcome_unknown") {
    return outcomeUnknownResponse(correlationId, headers);
  }
  if (status === "not_started") {
    return "not_started";
  }
  // failed or unexpected on open session → conflict
  throw new AtlasHttpError(
    409,
    "ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT",
    defaultMessageForCode("ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT"),
    false,
  );
}

async function runPaddleAndAttach(
  deps: HandlerDeps,
  reservation: ReserveBillingCheckoutSessionRow,
  actorUserId: string,
  companyId: string,
  idempotencyKey: string,
  correlationId: string,
  headers: HeadersInit,
): Promise<Response> {
  const paddleResult = await deps.paddle.createCheckout({
    external_price_id: reservation.external_price_id,
    checkout_page_url: reservation.checkout_page_url,
    payment_page_origin: reservation.payment_page_origin,
    checkout_path: reservation.checkout_path,
    company_id: companyId,
    checkout_session_id: reservation.session_id,
    offer_code: OFFER_CODE,
  });

  if (paddleResult.kind === "success") {
    let attach;
    try {
      attach = await deps.rpc.attachBillingCheckoutProviderResultServer({
        session_id: reservation.session_id,
        actor_user_id: actorUserId,
        expected_from: "processing",
        to_status: "created",
        external_transaction_id: paddleResult.external_transaction_id,
        checkout_url: paddleResult.checkout_url,
        error_sanitized: null,
        now: deps.clock().toISOString(),
      });
    } catch (err) {
      logSafe("error", "attach_created_failed_after_paddle_success", {
        correlation_id: correlationId,
        checkout_session_id: reservation.session_id,
        error_code: err instanceof AtlasHttpError
          ? err.errorCode
          : "ATLAS_INTERNAL_ERROR",
      });
      return outcomeUnknownResponse(correlationId, headers);
    }

    if (!attach.applied) {
      logSafe("warn", "attach_created_not_applied_after_paddle_success", {
        correlation_id: correlationId,
        checkout_session_id: reservation.session_id,
        applied: false,
      });
      return outcomeUnknownResponse(correlationId, headers);
    }

    logSafe("info", "checkout_created", {
      correlation_id: correlationId,
      checkout_session_id: reservation.session_id,
      reused: false,
    });
    return jsonResponse(
      200,
      successBody(reservation, paddleResult.checkout_url, false),
      headers,
    );
  }

  if (paddleResult.kind === "definitive_client_error") {
    let attach;
    try {
      attach = await deps.rpc.attachBillingCheckoutProviderResultServer({
        session_id: reservation.session_id,
        actor_user_id: actorUserId,
        expected_from: "processing",
        to_status: "failed",
        external_transaction_id: null,
        checkout_url: null,
        error_sanitized: paddleResult.sanitized_message,
        now: deps.clock().toISOString(),
      });
    } catch (err) {
      logSafe("error", "attach_failed_after_paddle_4xx", {
        correlation_id: correlationId,
        checkout_session_id: reservation.session_id,
        error_code: err instanceof AtlasHttpError
          ? err.errorCode
          : "ATLAS_INTERNAL_ERROR",
      });
      return outcomeUnknownResponse(correlationId, headers);
    }

    if (attach.applied === true) {
      return providerRejectedResponse(correlationId, headers);
    }

    // CAS lost: at most one bounded re-reserve; never call Paddle again.
    logSafe("warn", "attach_failed_not_applied_rereserve", {
      correlation_id: correlationId,
      checkout_session_id: reservation.session_id,
      applied: false,
    });

    let again: ReserveBillingCheckoutSessionRow;
    try {
      again = await deps.rpc.reserveBillingCheckoutSessionServer({
        company_id: companyId,
        actor_user_id: actorUserId,
        offer_code: OFFER_CODE,
        idempotency_key: idempotencyKey,
        now: deps.clock().toISOString(),
      });
      validateReservationRuntime(again);
    } catch (err) {
      logSafe("error", "rereserve_after_failed_attach_cas_loss", {
        correlation_id: correlationId,
        error_code: err instanceof AtlasHttpError
          ? err.errorCode
          : "ATLAS_INTERNAL_ERROR",
      });
      return outcomeUnknownResponse(correlationId, headers);
    }

    return mapAfterDefinitiveFailureRace(again, correlationId, headers);
  }

  // uncertain: timeout / network / 5xx / malformed / non-definitive 4xx
  let attachUnknown;
  try {
    attachUnknown = await deps.rpc.attachBillingCheckoutProviderResultServer({
      session_id: reservation.session_id,
      actor_user_id: actorUserId,
      expected_from: "processing",
      to_status: "outcome_unknown",
      external_transaction_id: null,
      checkout_url: null,
      error_sanitized: paddleResult.sanitized_message,
      now: deps.clock().toISOString(),
    });
  } catch (err) {
    logSafe("error", "attach_outcome_unknown_failed", {
      correlation_id: correlationId,
      checkout_session_id: reservation.session_id,
      paddle_kind: paddleResult.reason,
      error_code: err instanceof AtlasHttpError
        ? err.errorCode
        : "ATLAS_INTERNAL_ERROR",
    });
    return outcomeUnknownResponse(correlationId, headers);
  }

  if (!attachUnknown.applied) {
    logSafe("warn", "attach_outcome_unknown_not_applied", {
      correlation_id: correlationId,
      checkout_session_id: reservation.session_id,
      applied: false,
    });
  }

  return outcomeUnknownResponse(correlationId, headers);
}

/**
 * Process not_started: attach → processing, optionally one re-reserve, then Paddle.
 */
export async function processNotStarted(
  deps: HandlerDeps,
  reservation: ReserveBillingCheckoutSessionRow,
  actorUserId: string,
  companyId: string,
  idempotencyKey: string,
  correlationId: string,
  headers: HeadersInit,
  allowRereserve: boolean,
): Promise<Response> {
  let attach;
  try {
    attach = await deps.rpc.attachBillingCheckoutProviderResultServer({
      session_id: reservation.session_id,
      actor_user_id: actorUserId,
      expected_from: "not_started",
      to_status: "processing",
      external_transaction_id: null,
      checkout_url: null,
      error_sanitized: null,
      now: deps.clock().toISOString(),
    });
  } catch (err) {
    if (err instanceof AtlasHttpError) throw err;
    throw new AtlasHttpError(
      500,
      "ATLAS_INTERNAL_ERROR",
      "Failed to attach processing state",
    );
  }

  if (attach.applied === true) {
    return await runPaddleAndAttach(
      deps,
      reservation,
      actorUserId,
      companyId,
      idempotencyKey,
      correlationId,
      headers,
    );
  }

  // applied=false: race — at most one re-reserve; never loop into Paddle again here
  if (!allowRereserve) {
    return inProgressResponse(correlationId, headers);
  }

  logSafe("info", "attach_processing_not_applied_rereserve", {
    correlation_id: correlationId,
    checkout_session_id: reservation.session_id,
    applied: false,
  });

  const again = await deps.rpc.reserveBillingCheckoutSessionServer({
    company_id: companyId,
    actor_user_id: actorUserId,
    offer_code: OFFER_CODE,
    idempotency_key: idempotencyKey,
    now: deps.clock().toISOString(),
  });
  validateReservationRuntime(again);

  const mapped = mapReservationState(again, correlationId, headers);
  if (mapped !== "not_started") {
    return mapped;
  }

  // Still not_started after single re-reserve: do not loop; treat as in progress
  return inProgressResponse(correlationId, headers);
}

export async function handleCheckoutCreate(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const correlationId = deps.uuid();
  const origin = req.headers.get("Origin");

  let method: "OPTIONS" | "POST";
  try {
    method = assertPostOrOptions(req.method);
  } catch (err) {
    const decision = decideCors(origin, deps.corsAllowlist);
    const headers = new Headers(
      corsHeaders(decision.ok ? decision.allowOrigin : undefined),
    );
    headers.set("Allow", "OPTIONS, POST");
    if (err instanceof AtlasHttpError) {
      return jsonErrorResponse(
        err.status,
        err.errorCode,
        err.exposeMessage,
        err.retryable,
        correlationId,
        headers,
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
    // Auth first for POST (native no-Origin OK when JWT valid)
    const actor = await requireAuthenticatedActor(
      req.headers.get("Authorization"),
      deps.authLookup,
    );

    // Static config fail-closed before any DB transition.
    if (readPaddleSandboxApiKey(deps.env) === null) {
      throw new AtlasHttpError(
        503,
        "ATLAS_CHECKOUT_UNAVAILABLE",
        defaultMessageForCode("ATLAS_CHECKOUT_UNAVAILABLE"),
        false,
      );
    }

    requireJsonContentType(req.headers.get("Content-Type"));
    const idempotencyKey = requireIdempotencyKey(
      req.headers.get("Idempotency-Key"),
    );
    const bodyBytes = await readBodyWithLimit(req);
    const body = parseCheckoutCreateBody(bodyBytes);

    const reservation = await deps.rpc.reserveBillingCheckoutSessionServer({
      company_id: body.company_id,
      actor_user_id: actor.actor_user_id,
      offer_code: OFFER_CODE,
      idempotency_key: idempotencyKey,
      now: deps.clock().toISOString(),
    });

    validateReservationRuntime(reservation);

    const mapped = mapReservationState(
      reservation,
      correlationId,
      headers,
    );
    if (mapped !== "not_started") {
      return mapped;
    }

    return await processNotStarted(
      deps,
      reservation,
      actor.actor_user_id,
      body.company_id,
      idempotencyKey,
      correlationId,
      headers,
      true,
    );
  } catch (err) {
    if (err instanceof AtlasHttpError) {
      logSafe("warn", "checkout_create_error", {
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
    logSafe("error", "checkout_create_unexpected", {
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
  return (req) => handleCheckoutCreate(req, deps);
}

/** Re-export helpers useful for tests. */
export { defaultMessageForCode, httpStatusForAtlasCode, retryableForAtlasCode };
