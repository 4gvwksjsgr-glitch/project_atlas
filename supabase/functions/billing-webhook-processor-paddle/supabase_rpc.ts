/** Service-role RPC client for Paddle sandbox webhook processor. */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  AtlasHttpError,
  defaultMessageForCode,
  httpStatusForAtlasCode,
  normalizeRpcErrorCode,
  retryableForAtlasCode,
} from "../_shared/errors.ts";
import type {
  ApplyRow,
  ClaimNextRow,
  EnvReader,
  FailRow,
  ProcessorRpcClient,
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
): ProcessorRpcClient {
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
): ProcessorRpcClient {
  return {
    async claimNextPaddleSandboxWebhookEventServer() {
      const { data, error } = await client.rpc(
        "claim_next_paddle_sandbox_webhook_event_for_processing_server",
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as ClaimNextRow[] | null,
        "claim_next_paddle_sandbox_webhook_event_for_processing_server",
      );
    },

    async applyPaddleSandboxWebhookEventServer(inboxEventId) {
      const { data, error } = await client.rpc(
        "apply_paddle_sandbox_webhook_event_server",
        { p_inbox_event_id: inboxEventId },
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as ApplyRow[] | null,
        "apply_paddle_sandbox_webhook_event_server",
      );
    },

    async failPaddleSandboxWebhookEventProcessingServer(
      inboxEventId,
      errorCode,
    ) {
      const { data, error } = await client.rpc(
        "fail_paddle_sandbox_webhook_event_processing_server",
        {
          p_inbox_event_id: inboxEventId,
          p_error_code: errorCode,
        },
      );
      if (error) mapRpcFailure(error);
      return requireRow(
        data as FailRow[] | null,
        "fail_paddle_sandbox_webhook_event_processing_server",
      );
    },
  };
}
