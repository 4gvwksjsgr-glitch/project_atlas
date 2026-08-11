/** Service-role RPC client for paddle webhook inbox ingest. */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  AtlasHttpError,
  defaultMessageForCode,
  httpStatusForAtlasCode,
  normalizeRpcErrorCode,
  retryableForAtlasCode,
} from "../_shared/errors.ts";
import type {
  BillingWebhookRpcClient,
  EnvReader,
  IngestPaddleSandboxWebhookEventRow,
} from "./types.ts";

function mapRpcFailure(error: { message?: string; code?: string }): never {
  const code = normalizeRpcErrorCode(error.message ?? error.code);
  throw new AtlasHttpError(
    httpStatusForAtlasCode(code),
    code,
    defaultMessageForCode(code),
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
): BillingWebhookRpcClient {
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
): BillingWebhookRpcClient {
  return {
    async ingestPaddleSandboxWebhookEventServer(args) {
      const { data, error } = await client.rpc(
        "ingest_paddle_sandbox_webhook_event_server",
        {
          p_external_event_id: args.external_event_id,
          p_event_type: args.event_type,
          p_provider_created_at: args.provider_created_at,
          p_payload_hash: args.payload_hash,
          p_payload_json: args.payload_json,
          p_classification: args.classification,
          p_external_subscription_id: args.external_subscription_id ?? null,
        },
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as IngestPaddleSandboxWebhookEventRow[] | null,
        "ingest_paddle_sandbox_webhook_event_server",
      );
    },
  };
}
