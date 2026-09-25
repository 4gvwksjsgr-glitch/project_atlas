/**
 * billing-webhook-processor-paddle — Paddle Sandbox inbox processor orchestrator.
 */

import { maybeInvokeReferralAutoRedeem } from "../_shared/billing/referral_auto_redeem.ts";
import { createClient } from "@supabase/supabase-js";
import { createHandler } from "./handler.ts";
import { createServiceRpcClient } from "./supabase_rpc.ts";
import type { EnvReader, HandlerDeps } from "./types.ts";

function envReader(): EnvReader {
  return (key: string) => Deno.env.get(key);
}

function createDeps(): HandlerDeps {
  const env = envReader();
  const fetchImpl = fetch.bind(globalThis);
  const rpc = createServiceRpcClient(env, fetchImpl);

  return {
    clock: () => new Date(),
    uuid: () => crypto.randomUUID(),
    env,
    rpc,
    maybeAutoRedeem: async (companyId) => {
      const url = env("SUPABASE_URL");
      const key = env("SUPABASE_SERVICE_ROLE_KEY");
      await maybeInvokeReferralAutoRedeem(companyId, {
        env,
        fetch: fetchImpl,
        evaluate: async (id) => {
          if (!url || !key) return null;
          const client = createClient(url, key, {
            auth: {
              persistSession: false,
              autoRefreshToken: false,
              detectSessionInUrl: false,
            },
            global: { fetch: fetchImpl },
          });
          const { data, error } = await client.rpc(
            "evaluate_referral_auto_redemption_server",
            { p_company_id: id },
          );
          if (error || !data || !Array.isArray(data) || data.length === 0) {
            return null;
          }
          const row = data[0] as Record<string, unknown>;
          return {
            should_invoke_outbound: row.should_invoke_outbound === true,
            reason: typeof row.reason === "string" ? row.reason : null,
            open_operation_id: typeof row.open_operation_id === "string"
              ? row.open_operation_id
              : null,
            open_operation_status:
              typeof row.open_operation_status === "string"
                ? row.open_operation_status
                : null,
            pending_reward_count: typeof row.pending_reward_count === "number"
              ? row.pending_reward_count
              : null,
          };
        },
      });
    },
  };
}

const handler = createHandler(createDeps());

Deno.serve(handler);
