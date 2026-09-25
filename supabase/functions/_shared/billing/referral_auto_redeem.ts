/**
 * Best-effort auto referral redemption after authoritative provider apply.
 * Fail-closed: missing secret/URL => skip (no throw). Kill switch enforced in SQL/Edge.
 * Never invents entitlement; redeem Edge performs preview/PATCH/confirm gates.
 */

import { logSafe } from "../logging.ts";

export type EnvReader = (key: string) => string | undefined;

export const REDEEM_INVOKE_SECRET_ENV = "ATLAS_REFERRAL_REDEEM_INVOKE_SECRET";
export const REDEEM_INVOKE_HEADER = "x-atlas-referral-redeem-secret";

export interface AutoRedeemEvaluateRow {
  should_invoke_outbound: boolean;
  reason: string | null;
  open_operation_id: string | null;
  open_operation_status: string | null;
  pending_reward_count: number | null;
}

export interface ReferralAutoRedeemDeps {
  env: EnvReader;
  fetch: typeof fetch;
  /** Optional pre-check; when omitted, always attempts Edge invoke. */
  evaluate?: (companyId: string) => Promise<AutoRedeemEvaluateRow | null>;
  correlationId?: string;
}

export type AutoRedeemResult =
  | { kind: "skipped"; reason: string }
  | { kind: "invoked"; http_status: number }
  | { kind: "error"; sanitized: string };

/**
 * After webhook/reconcile subscription apply: evaluate then optionally POST redeem Edge.
 */
export async function maybeInvokeReferralAutoRedeem(
  companyId: string | null | undefined,
  deps: ReferralAutoRedeemDeps,
): Promise<AutoRedeemResult> {
  const id = companyId?.trim() ?? "";
  if (!id) {
    return { kind: "skipped", reason: "no_company" };
  }

  if (deps.evaluate) {
    let row: AutoRedeemEvaluateRow | null;
    try {
      row = await deps.evaluate(id);
    } catch {
      return { kind: "skipped", reason: "evaluate_failed" };
    }
    if (!row || row.should_invoke_outbound !== true) {
      return {
        kind: "skipped",
        reason: row?.reason ?? "evaluate_false",
      };
    }
  }

  const base = deps.env("SUPABASE_URL")?.trim() ?? "";
  const secret = deps.env(REDEEM_INVOKE_SECRET_ENV)?.trim() ?? "";
  if (!base || !secret) {
    logSafe("info", "referral_auto_redeem_skipped_config", {
      correlation_id: deps.correlationId,
      event: "auto_redeem_skip_config",
    });
    return { kind: "skipped", reason: "missing_config" };
  }

  const url = `${base.replace(/\/$/, "")}/functions/v1/billing-referral-redeem-paddle`;
  try {
    const res = await deps.fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [REDEEM_INVOKE_HEADER]: secret,
      },
      body: JSON.stringify({ company_id: id }),
    });
    logSafe("info", "referral_auto_redeem_invoked", {
      correlation_id: deps.correlationId,
      event: "auto_redeem_invoked",
      http_status: res.status,
    });
    return { kind: "invoked", http_status: res.status };
  } catch (err) {
    const msg = err instanceof Error ? err.message : "error";
    logSafe("warn", "referral_auto_redeem_invoke_failed", {
      correlation_id: deps.correlationId,
      event: "auto_redeem_invoke_failed",
      sanitized: msg.slice(0, 120),
    });
    return { kind: "error", sanitized: msg.slice(0, 120) };
  }
}
