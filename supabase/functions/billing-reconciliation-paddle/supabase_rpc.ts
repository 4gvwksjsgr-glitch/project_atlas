/**
 * Service-role RPC wrappers for billing reconciliation (D2-A).
 * actor_user_id is always a trusted server-side parameter from the future handler.
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  AtlasHttpError,
  defaultMessageForCode,
  httpStatusForAtlasCode,
  normalizeRpcErrorCode,
  retryableForAtlasCode,
} from "../_shared/errors.ts";
import type {
  ApplyBillingReconciliationArgs,
  ApplyBillingReconciliationResult,
  BillingReconciliationRpcClient,
  EnvReader,
  PrepareBillingReconciliationResult,
  ReconciliationFinalizerResult,
  RecordBillingReconciliationArgs,
  RecordBillingReconciliationResult,
} from "./types.ts";
import { RECONCILIATION_FINALIZER_RESULTS } from "./types.ts";

function mapRpcFailure(error: { message?: string; code?: string }): never {
  const code = normalizeRpcErrorCode(error.message ?? error.code);
  throw new AtlasHttpError(
    httpStatusForAtlasCode(code),
    code,
    defaultMessageForCode(code) === "Request failed"
      ? (code.startsWith("ATLAS_")
        ? code.replace(/^ATLAS_/, "").replace(/_/g, " ").toLowerCase()
        : "Request failed")
      : defaultMessageForCode(code),
    retryableForAtlasCode(code),
  );
}

function requireRow<T>(rows: T[] | null, label: string): T {
  if (!rows || rows.length === 0) {
    throw new AtlasHttpError(
      500,
      "ATLAS_INTERNAL_ERROR",
      `${label} returned no rows`,
    );
  }
  return rows[0]!;
}

function assertFinalizerResult(
  result: string,
): asserts result is ReconciliationFinalizerResult {
  if (
    !(RECONCILIATION_FINALIZER_RESULTS as readonly string[]).includes(result)
  ) {
    throw new AtlasHttpError(
      500,
      "ATLAS_INTERNAL_ERROR",
      "Invalid reconciliation finalizer result",
    );
  }
}

export function createServiceRpcClient(
  env: EnvReader,
  fetchImpl: typeof fetch = fetch,
): BillingReconciliationRpcClient {
  const url = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  }

  const client: SupabaseClient = createClient(url, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: fetchImpl },
  });

  return createRpcClientFromSupabase(client);
}

export function createRpcClientFromSupabase(
  client: SupabaseClient,
): BillingReconciliationRpcClient {
  return {
    async prepareCompanyBillingReconciliationServer(args) {
      const { data, error } = await client.rpc(
        "prepare_company_billing_reconciliation_server",
        {
          p_company_id: args.company_id,
          p_actor_user_id: args.actor_user_id,
        },
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as PrepareBillingReconciliationResult[] | null,
        "prepare_company_billing_reconciliation_server",
      );
    },

    async applyCompanyBillingReconciliationServer(
      args: ApplyBillingReconciliationArgs,
    ) {
      const { data, error } = await client.rpc(
        "apply_company_billing_reconciliation_server",
        {
          p_company_id: args.company_id,
          p_actor_user_id: args.actor_user_id,
          p_expected_external_subscription_id:
            args.expected_external_subscription_id,
          p_expected_external_customer_id: args.expected_external_customer_id,
          p_expected_linkage_fingerprint: args.expected_linkage_fingerprint,
          p_external_price_id: args.external_price_id,
          p_provider_subscription_status: args.provider_subscription_status,
          p_current_period_start: args.current_period_start,
          p_current_period_end: args.current_period_end,
          p_cancel_at_period_end: args.cancel_at_period_end,
          p_canceled_at: args.canceled_at,
          p_provider_updated_at: args.provider_updated_at,
        },
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as ApplyBillingReconciliationResult[] | null,
        "apply_company_billing_reconciliation_server",
      );
    },

    async recordCompanyBillingReconciliationResultServer(
      args: RecordBillingReconciliationArgs,
    ) {
      assertFinalizerResult(args.result);
      const { data, error } = await client.rpc(
        "record_company_billing_reconciliation_result_server",
        {
          p_company_id: args.company_id,
          p_actor_user_id: args.actor_user_id,
          p_expected_external_subscription_id:
            args.expected_external_subscription_id,
          p_expected_external_customer_id: args.expected_external_customer_id,
          p_expected_linkage_fingerprint: args.expected_linkage_fingerprint,
          p_result: args.result,
          p_error_sanitized: args.error_sanitized,
          p_provider_updated_at: args.provider_updated_at,
        },
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as RecordBillingReconciliationResult[] | null,
        "record_company_billing_reconciliation_result_server",
      );
    },
  };
}
