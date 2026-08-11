/**
 * billing-webhook-paddle — Paddle Sandbox webhook inbox entry.
 */

import { createHandler } from "./handler.ts";
import { createServiceRpcClient } from "./supabase_rpc.ts";
import type { EnvReader, HandlerDeps } from "./types.ts";

function envReader(): EnvReader {
  return (key: string) => Deno.env.get(key);
}

function createDeps(): HandlerDeps {
  const env = envReader();
  const fetchImpl = fetch.bind(globalThis);
  return {
    clock: () => new Date(),
    uuid: () => crypto.randomUUID(),
    env,
    rpc: createServiceRpcClient(env, fetchImpl),
  };
}

const handler = createHandler(createDeps());

Deno.serve(handler);
