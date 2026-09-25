/**
 * Unit tests for referral auto-redeem helper (no real network).
 */

import { assertEquals } from "@std/assert";
import {
  maybeInvokeReferralAutoRedeem,
  REDEEM_INVOKE_HEADER,
  REDEEM_INVOKE_SECRET_ENV,
} from "./referral_auto_redeem.ts";

Deno.test("auto redeem skips without company", async () => {
  const r = await maybeInvokeReferralAutoRedeem(null, {
    env: () => undefined,
    fetch: async () => {
      throw new Error("network must not be used");
    },
  });
  assertEquals(r.kind, "skipped");
});

Deno.test("auto redeem skips when evaluate false (kill switch)", async () => {
  let fetches = 0;
  const r = await maybeInvokeReferralAutoRedeem("c1", {
    env: () => "x",
    fetch: async () => {
      fetches++;
      return new Response("{}", { status: 200 });
    },
    evaluate: async () => ({
      should_invoke_outbound: false,
      reason: "ATLAS_REFERRAL_REDEMPTION_DISABLED",
      open_operation_id: null,
      open_operation_status: null,
      pending_reward_count: 2,
    }),
  });
  assertEquals(r.kind, "skipped");
  assertEquals(fetches, 0);
});

Deno.test("auto redeem invokes Edge once when evaluate true", async () => {
  let fetches = 0;
  let header = "";
  const r = await maybeInvokeReferralAutoRedeem("c1", {
    env: (k) => {
      if (k === "SUPABASE_URL") return "http://127.0.0.1:54321";
      if (k === REDEEM_INVOKE_SECRET_ENV) return "secret";
      return undefined;
    },
    fetch: async (_url, init) => {
      fetches++;
      header = (init?.headers as Record<string, string>)?.[REDEEM_INVOKE_HEADER] ??
        "";
      return new Response(JSON.stringify({ result: "no_pending" }), {
        status: 200,
      });
    },
    evaluate: async () => ({
      should_invoke_outbound: true,
      reason: "eligible_pending",
      open_operation_id: null,
      open_operation_status: null,
      pending_reward_count: 1,
    }),
  });
  assertEquals(r.kind, "invoked");
  assertEquals(fetches, 1);
  assertEquals(header, "secret");
});
