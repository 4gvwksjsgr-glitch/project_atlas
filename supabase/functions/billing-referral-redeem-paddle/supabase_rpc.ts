/** Service-role RPC client for referral redemption. */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type {
  ClaimRedemptionRow,
  ConfirmRedemptionRow,
  EnvReader,
  OpenRedemptionRow,
  ReferralRedeemRpcClient,
} from "./types.ts";

function requireRow<T>(rows: T[] | null, label: string): T {
  if (!rows || rows.length === 0) {
    throw new Error(`${label} returned no rows`);
  }
  return rows[0]!;
}

export function createServiceRpcClient(
  env: EnvReader,
  fetchImpl: typeof fetch = fetch,
): ReferralRedeemRpcClient {
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
): ReferralRedeemRpcClient {
  return {
    async claimReferralRedemptionOperationServer(companyId) {
      const { data, error } = await client.rpc(
        "claim_referral_redemption_operation_server",
        { p_company_id: companyId },
      );
      if (error) throw new Error(error.message);
      return requireRow(data as ClaimRedemptionRow[], "claim");
    },
    async updateReferralRedemptionOperationStatusServer(args) {
      const { data, error } = await client.rpc(
        "update_referral_redemption_operation_status_server",
        {
          p_operation_id: args.operation_id,
          p_status: args.status,
          p_error_code: args.error_code ?? null,
          p_set_previewed: args.set_previewed ?? false,
          p_set_provider_accepted: args.set_provider_accepted ?? false,
          p_bump_attempt: args.bump_attempt ?? false,
          p_expected_old: args.expected_old ?? null,
          p_target: args.target ?? null,
          p_subscription_snapshot: args.subscription_snapshot ?? null,
        },
      );
      if (error) throw new Error(error.message);
      return data === true;
    },
    async confirmReferralRedemptionOperationServer(args) {
      const { data, error } = await client.rpc(
        "confirm_referral_redemption_operation_server",
        {
          p_company_id: args.company_id,
          p_observed_next_billed_at: args.observed_next_billed_at ?? null,
          p_provider_subscription_id: args.provider_subscription_id ?? null,
        },
      );
      if (error) throw new Error(error.message);
      return requireRow(data as ConfirmRedemptionRow[], "confirm");
    },
    async abortReferralRedemptionOperationServer(operationId, errorCode) {
      const { data, error } = await client.rpc(
        "abort_referral_redemption_operation_server",
        { p_operation_id: operationId, p_error_code: errorCode },
      );
      if (error) throw new Error(error.message);
      return data === true;
    },
    async getOpenReferralRedemptionOperationServer(companyId) {
      const { data, error } = await client.rpc(
        "get_open_referral_redemption_operation_server",
        { p_company_id: companyId },
      );
      if (error) throw new Error(error.message);
      const rows = data as OpenRedemptionRow[] | null;
      if (!rows || rows.length === 0) return null;
      return rows[0]!;
    },
  };
}
