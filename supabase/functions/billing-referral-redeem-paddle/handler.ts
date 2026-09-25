/**
 * Referral reward redemption handler.
 * Fail-closed: kill switch / eligibility / preview must pass before PATCH.
 * Never mark rewards redeemed on HTTP 200 alone — confirm via period/webhook.
 */

import { timingSafeEqualString } from "../billing-webhook-processor-paddle/secret.ts";
import type {
  ClaimRedemptionRow,
  HandlerDeps,
  OpenRedemptionRow,
} from "./types.ts";
import {
  REDEEM_INVOKE_HEADER,
  REDEEM_INVOKE_SECRET_ENV,
  REDEEM_MAX_BODY_BYTES,
} from "./types.ts";

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function sameInstant(a: string | null | undefined, b: string | null | undefined): boolean {
  if (!a || !b) return false;
  const da = Date.parse(a);
  const db = Date.parse(b);
  if (Number.isNaN(da) || Number.isNaN(db)) return a === b;
  return da === db;
}

function liveNextBilledAt(data: {
  next_billed_at?: string | null;
  current_billing_period?: { ends_at?: string | null } | null;
}): string | null {
  const direct = data.next_billed_at?.trim();
  if (direct) return direct;
  const ends = data.current_billing_period?.ends_at?.trim();
  return ends || null;
}

async function assertInvokeSecret(
  req: Request,
  env: HandlerDeps["env"],
): Promise<boolean> {
  const expected = env(REDEEM_INVOKE_SECRET_ENV)?.trim() ?? "";
  if (!expected) return false;
  const provided = req.headers.get(REDEEM_INVOKE_HEADER)?.trim() ?? "";
  if (!provided) return false;
  return await timingSafeEqualString(provided, expected);
}

async function runProviderPath(
  deps: HandlerDeps,
  companyId: string,
  claim: ClaimRedemptionRow | OpenRedemptionRow,
): Promise<Response> {
  const operationId = "operation_id" in claim
    ? claim.operation_id
    : (claim as OpenRedemptionRow).id;
  const expectedOld = claim.expected_old_next_billed_at;
  const target = claim.target_next_billed_at;
  const snapshot = "provider_subscription_id" in claim
    ? claim.provider_subscription_id
    : (claim as OpenRedemptionRow).provider_subscription_id_snapshot;

  if (!operationId || !expectedOld || !target || !snapshot) {
    return jsonResponse(200, {
      result: "error",
      error_code: "ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT",
    });
  }

  const got = await deps.paddle.getSubscription(snapshot);
  if (got.kind !== "success") {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "needs_reconcile",
      error_code: got.kind === "not_found"
        ? "ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED"
        : "ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN",
      bump_attempt: true,
    });
    return jsonResponse(200, {
      result: "needs_reconcile",
      error_code: "ATLAS_REFERRAL_RECONCILE_REQUIRED",
      paddle_calls: { get: 1, preview: 0, patch: 0 },
    });
  }

  const liveSubId = got.data.id?.trim() ?? "";
  if (liveSubId && liveSubId !== snapshot) {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "needs_reconcile",
      error_code: "ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED",
      bump_attempt: true,
    });
    return jsonResponse(200, {
      result: "provider_subscription_changed",
      error_code: "ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED",
      paddle_calls: { get: 1, preview: 0, patch: 0 },
    });
  }

  const live = liveNextBilledAt(got.data);

  if (sameInstant(live, target)) {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "provider_accepted",
      set_provider_accepted: true,
      bump_attempt: true,
    });
    const confirmed = await deps.rpc.confirmReferralRedemptionOperationServer({
      company_id: companyId,
      observed_next_billed_at: live,
      provider_subscription_id: snapshot,
    });
    return jsonResponse(200, {
      result: confirmed.outcome,
      operation_id: operationId,
      paddle_calls: { get: 1, preview: 0, patch: 0 },
    });
  }

  if (!sameInstant(live, expectedOld)) {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "needs_reconcile",
      error_code: "ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT",
      bump_attempt: true,
    });
    return jsonResponse(200, {
      result: "conflict_third_date",
      error_code: "ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT",
      paddle_calls: { get: 1, preview: 0, patch: 0 },
    });
  }

  await deps.rpc.updateReferralRedemptionOperationStatusServer({
    operation_id: operationId,
    status: "previewing",
    bump_attempt: true,
  });

  const preview = await deps.paddle.previewNextBilledAt({
    external_subscription_id: snapshot,
    next_billed_at: target,
    proration_billing_mode: "do_not_bill",
  });

  if (preview.kind !== "safe") {
    const code = preview.kind === "unsafe_immediate_charge" ||
        preview.kind === "unsafe_unexpected"
      ? "ATLAS_REFERRAL_PREVIEW_NOT_SAFE"
      : "ATLAS_REFERRAL_PROVIDER_REJECTED";
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "retryable_failed",
      error_code: code,
    });
    const body: Record<string, unknown> = {
      result: "preview_not_safe",
      error_code: code,
      paddle_calls: { get: 1, preview: 1, patch: 0 },
    };
    // Privileged redeem Edge only: expose already-sanitized Paddle status/code
    // for definitive preview rejections (e.g. HTTP 409 conflict codes).
    if (preview.kind === "definitive_client_error") {
      body.provider_http_status = preview.http_status;
      if (
        typeof preview.paddle_error_code === "string" &&
        preview.paddle_error_code.length > 0
      ) {
        body.provider_error_code = preview.paddle_error_code;
      }
    }
    return jsonResponse(200, body);
  }

  await deps.rpc.updateReferralRedemptionOperationStatusServer({
    operation_id: operationId,
    status: "ready_to_apply",
    set_previewed: true,
  });

  const updated = await deps.paddle.updateNextBilledAt({
    external_subscription_id: snapshot,
    next_billed_at: target,
    proration_billing_mode: "do_not_bill",
  });

  if (updated.kind === "uncertain") {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "needs_reconcile",
      error_code: "ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN",
    });
    return jsonResponse(200, {
      result: "needs_reconcile",
      error_code: "ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN",
      paddle_calls: { get: 1, preview: 1, patch: 1 },
    });
  }

  if (updated.kind !== "success") {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "retryable_failed",
      error_code: "ATLAS_REFERRAL_PROVIDER_REJECTED",
    });
    return jsonResponse(200, {
      result: "provider_rejected",
      error_code: "ATLAS_REFERRAL_PROVIDER_REJECTED",
      paddle_calls: { get: 1, preview: 1, patch: 1 },
    });
  }

  const returned = updated.next_billed_at ??
    updated.current_period_ends_at ??
    null;

  if (sameInstant(returned, target)) {
    await deps.rpc.updateReferralRedemptionOperationStatusServer({
      operation_id: operationId,
      status: "provider_accepted",
      set_provider_accepted: true,
    });
    return jsonResponse(200, {
      result: "provider_accepted",
      operation_id: operationId,
      note: "await_webhook_confirm",
      paddle_calls: { get: 1, preview: 1, patch: 1 },
    });
  }

  await deps.rpc.updateReferralRedemptionOperationStatusServer({
    operation_id: operationId,
    status: "needs_reconcile",
    error_code: "ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT",
  });
  return jsonResponse(200, {
    result: "needs_reconcile",
    error_code: "ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT",
    paddle_calls: { get: 1, preview: 1, patch: 1 },
  });
}

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return jsonResponse(405, { error_code: "ATLAS_METHOD_NOT_ALLOWED" });
    }

    const okSecret = await assertInvokeSecret(req, deps.env);
    if (!okSecret) {
      return jsonResponse(401, { error_code: "ATLAS_UNAUTHORIZED" });
    }

    const raw = await req.arrayBuffer();
    if (raw.byteLength > REDEEM_MAX_BODY_BYTES) {
      return jsonResponse(413, { error_code: "ATLAS_PAYLOAD_TOO_LARGE" });
    }

    let body: { company_id?: string };
    try {
      body = JSON.parse(new TextDecoder().decode(raw)) as { company_id?: string };
    } catch {
      return jsonResponse(400, { error_code: "ATLAS_INVALID_REQUEST" });
    }

    const companyId = body.company_id?.trim();
    if (!companyId) {
      return jsonResponse(400, { error_code: "ATLAS_COMPANY_ID_REQUIRED" });
    }

    let claim: ClaimRedemptionRow;
    try {
      claim = await deps.rpc.claimReferralRedemptionOperationServer(companyId);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "error";
      return jsonResponse(500, {
        error_code: "ATLAS_INTERNAL_ERROR",
        sanitized: msg.slice(0, 120),
      });
    }

    if (claim.outcome === "blocked" &&
      claim.error_code === "ATLAS_REFERRAL_REDEMPTION_DISABLED") {
      return jsonResponse(200, {
        result: "disabled",
        error_code: "ATLAS_REFERRAL_REDEMPTION_DISABLED",
        paddle_calls: { get: 0, preview: 0, patch: 0 },
      });
    }

    if (claim.outcome === "no_pending") {
      return jsonResponse(200, {
        result: "no_pending",
        paddle_calls: { get: 0, preview: 0, patch: 0 },
      });
    }

    if (claim.outcome === "blocked") {
      return jsonResponse(200, {
        result: "blocked",
        error_code: claim.error_code,
        paddle_calls: { get: 0, preview: 0, patch: 0 },
      });
    }

    if (claim.outcome === "existing_open" || claim.outcome === "claimed") {
      return await runProviderPath(deps, companyId, claim);
    }

    return jsonResponse(200, {
      result: claim.outcome,
      error_code: claim.error_code,
      paddle_calls: { get: 0, preview: 0, patch: 0 },
    });
  };
}
