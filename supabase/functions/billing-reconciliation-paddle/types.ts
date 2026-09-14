/**
 * Types for billing-reconciliation-paddle Edge Function (D2).
 */

import type { AuthUserLookup } from "../_shared/auth.ts";
import type { BillingProviderSubscriptionReader } from "../_shared/providers/paddle/paddle_types.ts";

export type EnvReader = (key: string) => string | undefined;

/** Finalizer caller-requested results only (matches SQL allowlist). */
export type ReconciliationFinalizerResult =
  | "provider_error"
  | "not_found"
  | "invalid_provider_response";

export const RECONCILIATION_FINALIZER_RESULTS = [
  "provider_error",
  "not_found",
  "invalid_provider_response",
] as const satisfies readonly ReconciliationFinalizerResult[];

export interface PrepareBillingReconciliationResult {
  company_id: string;
  provider_code: string;
  provider_environment: string;
  external_subscription_id: string;
  external_customer_id: string;
  external_price_id: string | null;
  expected_webhook_watermark: string | null;
  expected_provider_state_version: string | null;
  expected_linkage_fingerprint: string;
  expected_local_state_fingerprint: string;
}

export interface ApplyBillingReconciliationResult {
  result: string;
  company_id: string;
  provider_updated_at: string | null;
}

export interface RecordBillingReconciliationResult {
  result: string;
  company_id: string;
  recorded: boolean;
}

export interface ApplyBillingReconciliationArgs {
  company_id: string;
  actor_user_id: string;
  expected_external_subscription_id: string;
  expected_external_customer_id: string;
  expected_linkage_fingerprint: string;
  external_price_id: string;
  provider_subscription_status: string;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  canceled_at: string | null;
  provider_updated_at: string;
}

export interface RecordBillingReconciliationArgs {
  company_id: string;
  actor_user_id: string;
  expected_external_subscription_id: string;
  expected_external_customer_id: string;
  expected_linkage_fingerprint: string;
  result: ReconciliationFinalizerResult;
  error_sanitized: string | null;
  provider_updated_at: string | null;
}

/** Normalized authoritative snapshot for apply RPC (no entitlement mapping). */
export interface NormalizedProviderSubscriptionSnapshot {
  external_subscription_id: string;
  external_customer_id: string;
  external_price_id: string;
  provider_subscription_status: string;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  canceled_at: string | null;
  provider_updated_at: string;
}

export interface BillingReconciliationRpcClient {
  prepareCompanyBillingReconciliationServer(args: {
    company_id: string;
    actor_user_id: string;
  }): Promise<PrepareBillingReconciliationResult>;

  applyCompanyBillingReconciliationServer(
    args: ApplyBillingReconciliationArgs,
  ): Promise<ApplyBillingReconciliationResult>;

  recordCompanyBillingReconciliationResultServer(
    args: RecordBillingReconciliationArgs,
  ): Promise<RecordBillingReconciliationResult>;
}

/** Apply / finalizer results accepted by the Edge orchestrator. */
export const KNOWN_RECONCILIATION_OUTCOMES = [
  "updated",
  "in_sync",
  "stale_provider_state",
  "busy",
  "conflict",
  "unlinked",
  "stale_snapshot",
  "catalog_mismatch",
  "unsupported_state",
  "invalid_provider_response",
  "not_found",
  "provider_error",
] as const;

export type KnownReconciliationOutcome =
  typeof KNOWN_RECONCILIATION_OUTCOMES[number];

export interface ReconciliationSuccessBody {
  schema_version: 1;
  ok: true;
  data: {
    company_id: string;
    result: "updated" | "in_sync";
    provider_updated_at: string | null;
  };
}

export interface HandlerDeps {
  fetch: typeof fetch;
  clock: () => Date;
  uuid: () => string;
  authLookup: AuthUserLookup;
  rpc: BillingReconciliationRpcClient;
  paddle: BillingProviderSubscriptionReader;
  corsAllowlist: readonly string[];
  env: EnvReader;
}
