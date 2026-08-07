/**
 * Service-role RPC wrappers for billing checkout create.
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
  AttachBillingCheckoutProviderResultRow,
  BillingCheckoutRpcClient,
  EnvReader,
  ReserveBillingCheckoutSessionRow,
} from "./types.ts";

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

export function createServiceRpcClient(
  env: EnvReader,
  fetchImpl: typeof fetch = fetch,
): BillingCheckoutRpcClient {
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
): BillingCheckoutRpcClient {
  return {
    async reserveBillingCheckoutSessionServer(args) {
      const { data, error } = await client.rpc(
        "reserve_billing_checkout_session_server",
        {
          p_company_id: args.company_id,
          p_actor_user_id: args.actor_user_id,
          p_offer_code: args.offer_code,
          p_idempotency_key: args.idempotency_key,
          ...(args.now ? { p_now: args.now } : {}),
        },
      );
      if (error) mapRpcFailure(error);
      const row = requireRow(
        data as ReserveBillingCheckoutSessionRow[] | null,
        "reserve_billing_checkout_session_server",
      );
      return row;
    },

    async attachBillingCheckoutProviderResultServer(args) {
      const { data, error } = await client.rpc(
        "attach_billing_checkout_provider_result_server",
        {
          p_session_id: args.session_id,
          p_actor_user_id: args.actor_user_id,
          p_expected_from: args.expected_from,
          p_to_status: args.to_status,
          p_external_transaction_id: args.external_transaction_id ?? null,
          p_checkout_url: args.checkout_url ?? null,
          p_error_sanitized: args.error_sanitized ?? null,
          ...(args.now ? { p_now: args.now } : {}),
        },
      );
      if (error) mapRpcFailure(error);
      const row = requireRow(
        data as AttachBillingCheckoutProviderResultRow[] | null,
        "attach_billing_checkout_provider_result_server",
      );
      return row;
    },
  };
}
