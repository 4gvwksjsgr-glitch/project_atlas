/**
 * billing-referral-redeem-paddle handler tests — mocked Paddle only.
 */

import { assertEquals } from "@std/assert";
import { createHandler } from "./handler.ts";
import type {
  ClaimRedemptionRow,
  HandlerDeps,
  ReferralRedeemPaddleClient,
  ReferralRedeemRpcClient,
} from "./types.ts";
import { REDEEM_INVOKE_HEADER, REDEEM_INVOKE_SECRET_ENV } from "./types.ts";

const SECRET = "test-redeem-secret";
const COMPANY = "11111111-1111-1111-1111-111111111111";
const OP = "22222222-2222-2222-2222-222222222222";
const SUB = "sub_01habcdefghijklmnopqrstuvw";
const OLD = "2026-10-15T10:00:00.000Z";
const TARGET = "2027-01-15T10:00:00.000Z";

function baseClaim(over: Partial<ClaimRedemptionRow> = {}): ClaimRedemptionRow {
  return {
    outcome: "claimed",
    operation_id: OP,
    reward_count: 3,
    reward_ids: ["a", "b", "c"],
    expected_old_next_billed_at: OLD,
    target_next_billed_at: TARGET,
    provider_subscription_id: SUB,
    operation_status: "claimed",
    error_code: null,
    ...over,
  };
}

function makeDeps(opts: {
  claim?: ClaimRedemptionRow;
  getKind?: "success" | "not_found";
  liveNext?: string;
  previewKind?: "safe" | "unsafe_immediate_charge";
  updateKind?: "success" | "uncertain";
  updateNext?: string;
}): {
  deps: HandlerDeps;
  calls: { get: number; preview: number; patch: number; status: string[] };
} {
  const calls = { get: 0, preview: 0, patch: 0, status: [] as string[] };
  const rpc: ReferralRedeemRpcClient = {
    async claimReferralRedemptionOperationServer() {
      return opts.claim ?? baseClaim();
    },
    async updateReferralRedemptionOperationStatusServer(args) {
      calls.status.push(args.status);
      return true;
    },
    async confirmReferralRedemptionOperationServer() {
      return {
        outcome: "confirmed",
        operation_id: OP,
        rewards_redeemed: 3,
        error_code: null,
      };
    },
    async abortReferralRedemptionOperationServer() {
      return true;
    },
    async getOpenReferralRedemptionOperationServer() {
      return null;
    },
  };

  const paddle: ReferralRedeemPaddleClient = {
    async getSubscription() {
      calls.get++;
      if (opts.getKind === "not_found") {
        return {
          kind: "not_found",
          sanitized_message: "missing",
        };
      }
      return {
        kind: "success",
        data: {
          id: SUB,
          status: "active",
          next_billed_at: opts.liveNext ?? OLD,
          current_billing_period: {
            starts_at: "2026-09-15T10:00:00.000Z",
            ends_at: opts.liveNext ?? OLD,
          },
        },
      };
    },
    async previewNextBilledAt() {
      calls.preview++;
      if (opts.previewKind === "unsafe_immediate_charge") {
        return {
          kind: "unsafe_immediate_charge",
          sanitized_message: "charge",
          immediate_grand_total: "1000",
        };
      }
      return {
        kind: "safe",
        data: {
          id: SUB,
          next_billed_at: TARGET,
        },
        preview_next_billed_at: TARGET,
      };
    },
    async updateNextBilledAt() {
      calls.patch++;
      if (opts.updateKind === "uncertain") {
        return {
          kind: "uncertain",
          reason: "timeout",
          sanitized_message: "timeout",
        };
      }
      return {
        kind: "success",
        data: { id: SUB, next_billed_at: opts.updateNext ?? TARGET },
        next_billed_at: opts.updateNext ?? TARGET,
        current_period_ends_at: opts.updateNext ?? TARGET,
      };
    },
  };

  const deps: HandlerDeps = {
    fetch: async () => {
      throw new Error("network must not be used in tests");
    },
    clock: () => new Date("2026-09-22T12:00:00.000Z"),
    env: (k) => k === REDEEM_INVOKE_SECRET_ENV ? SECRET : undefined,
    rpc,
    paddle,
  };
  return { deps, calls };
}

async function post(
  handler: (req: Request) => Promise<Response>,
  body: unknown,
  secret = SECRET,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const res = await handler(
    new Request("http://local/redeem", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [REDEEM_INVOKE_HEADER]: secret,
      },
      body: JSON.stringify(body),
    }),
  );
  return { status: res.status, json: await res.json() };
}

Deno.test("disabled → zero paddle calls", async () => {
  const { deps, calls } = makeDeps({
    claim: baseClaim({
      outcome: "blocked",
      error_code: "ATLAS_REFERRAL_REDEMPTION_DISABLED",
      operation_id: null,
      expected_old_next_billed_at: null,
      target_next_billed_at: null,
      provider_subscription_id: null,
    }),
  });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "disabled");
  assertEquals(calls.get + calls.preview + calls.patch, 0);
});

Deno.test("no pending → zero paddle", async () => {
  const { deps, calls } = makeDeps({
    claim: baseClaim({
      outcome: "no_pending",
      operation_id: null,
      error_code: "ATLAS_REFERRAL_NO_PENDING_REWARDS",
    }),
  });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "no_pending");
  assertEquals(calls.patch, 0);
});

Deno.test("blocked past_due → zero PATCH", async () => {
  const { deps, calls } = makeDeps({
    claim: baseClaim({
      outcome: "blocked",
      error_code: "ATLAS_REFERRAL_PROVIDER_PAST_DUE",
      operation_id: null,
    }),
  });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "blocked");
  assertEquals(calls.patch, 0);
});

Deno.test("preview unsafe → zero PATCH", async () => {
  const { deps, calls } = makeDeps({
    previewKind: "unsafe_immediate_charge",
  });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "preview_not_safe");
  assertEquals(calls.get, 1);
  assertEquals(calls.preview, 1);
  assertEquals(calls.patch, 0);
});

Deno.test("happy path: GET + preview + one PATCH", async () => {
  const { deps, calls } = makeDeps({});
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "provider_accepted");
  assertEquals(calls.get, 1);
  assertEquals(calls.preview, 1);
  assertEquals(calls.patch, 1);
});

Deno.test("timeout after PATCH → needs_reconcile", async () => {
  const { deps, calls } = makeDeps({ updateKind: "uncertain" });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "needs_reconcile");
  assertEquals(calls.patch, 1);
});

Deno.test("GET exact target → confirm, zero PATCH", async () => {
  const { deps, calls } = makeDeps({ liveNext: TARGET });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "confirmed");
  assertEquals(calls.patch, 0);
});

Deno.test("GET third date → conflict, zero PATCH", async () => {
  const { deps, calls } = makeDeps({
    liveNext: "2026-11-01T10:00:00.000Z",
  });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "conflict_third_date");
  assertEquals(calls.patch, 0);
});

Deno.test("GET old value → one PATCH only (no target=live+N)", async () => {
  const { deps, calls } = makeDeps({ liveNext: OLD });
  const out = await post(createHandler(deps), { company_id: COMPANY });
  assertEquals(out.json.result, "provider_accepted");
  assertEquals(calls.get, 1);
  assertEquals(calls.preview, 1);
  assertEquals(calls.patch, 1);
});

Deno.test("unauthorized without secret", async () => {
  const { deps } = makeDeps({});
  const out = await post(createHandler(deps), { company_id: COMPANY }, "wrong");
  assertEquals(out.status, 401);
});
