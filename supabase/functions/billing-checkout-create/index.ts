/**
 * billing-checkout-create — local Paddle sandbox checkout Edge Function entry.
 */

import { createAuthUserLookup } from "../_shared/auth.ts";
import { parseCorsAllowlist } from "../_shared/http.ts";
import { createPaddleSandboxCheckoutAdapter } from "../_shared/providers/paddle/paddle_adapter.ts";
import { createHandler } from "./handler.ts";
import { createServiceRpcClient } from "./supabase_rpc.ts";
import type { EnvReader, HandlerDeps } from "./types.ts";

function envReader(): EnvReader {
  return (key: string) => Deno.env.get(key);
}

function createDeps(): HandlerDeps {
  const env = envReader();
  const fetchImpl = fetch.bind(globalThis);
  const supabaseUrl = env("SUPABASE_URL") ?? "";
  const anonKey = env("SUPABASE_ANON_KEY") ?? "";

  return {
    fetch: fetchImpl,
    clock: () => new Date(),
    uuid: () => crypto.randomUUID(),
    authLookup: createAuthUserLookup(supabaseUrl, anonKey, fetchImpl),
    rpc: createServiceRpcClient(env, fetchImpl),
    paddle: createPaddleSandboxCheckoutAdapter({ fetch: fetchImpl, env }),
    corsAllowlist: parseCorsAllowlist(env("CORS_ALLOWLIST")),
    env,
  };
}

const handler = createHandler(createDeps());

Deno.serve(handler);
