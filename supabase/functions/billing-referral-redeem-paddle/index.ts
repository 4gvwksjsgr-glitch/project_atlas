/**
 * billing-referral-redeem-paddle — local Edge Function (NOT deployed in Step 18B).
 * Privileged redemption of referral Premium months via Paddle next_billed_at + do_not_bill.
 */

import {
  getPaddleSandboxSubscription,
  previewPaddleSandboxSubscriptionNextBilledAt,
  updatePaddleSandboxSubscriptionNextBilledAt,
} from "../_shared/providers/paddle/paddle_adapter.ts";
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
    fetch: fetchImpl,
    clock: () => new Date(),
    env,
    rpc: createServiceRpcClient(env, fetchImpl),
    paddle: {
      getSubscription: (id) =>
        getPaddleSandboxSubscription(id, { fetch: fetchImpl, env }),
      previewNextBilledAt: (input) =>
        previewPaddleSandboxSubscriptionNextBilledAt(input, {
          fetch: fetchImpl,
          env,
        }),
      updateNextBilledAt: (input) =>
        updatePaddleSandboxSubscriptionNextBilledAt(input, {
          fetch: fetchImpl,
          env,
        }),
    },
  };
}

Deno.serve(createHandler(createDeps()));
