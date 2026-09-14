// deno-lint-ignore-file require-await
/**
 * billing-reconciliation-paddle handler tests — injected deps only.
 */

import { assertEquals } from "@std/assert";
import type { AuthUserLookup } from "../_shared/auth.ts";
import type { PaddleGetSubscriptionResult } from "../_shared/providers/paddle/paddle_types.ts";
import { createHandler } from "./handler.ts";
import type {
  ApplyBillingReconciliationArgs,
  ApplyBillingReconciliationResult,
  BillingReconciliationRpcClient,
  HandlerDeps,
  PrepareBillingReconciliationResult,
  ReconciliationFinalizerResult,
  RecordBillingReconciliationArgs,
  RecordBillingReconciliationResult,
} from "./types.ts";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const ACTOR = "22222222-2222-4222-8222-222222222222";
const OTHER_ACTOR = "33333333-3333-4333-8333-333333333333";
const CORRELATION = "44444444-4444-4444-8444-444444444444";
const SUB = "sub_01h4examplesubid0000000001";
const CTM = "ctm_01h4examplecustid000000001";
const PRI = "pri_01h4examplepriceid00000001";
const LINK_FP = "link_fp_abc";
const UPDATED = "2026-09-14T10:00:00.000Z";
const PERIOD_START = "2026-09-01T00:00:00.000Z";
const PERIOD_END = "2026-10-01T00:00:00.000Z";

function prepareRow(
  overrides: Partial<PrepareBillingReconciliationResult> = {},
): PrepareBillingReconciliationResult {
  return {
    company_id: COMPANY,
    provider_code: "paddle",
    provider_environment: "test",
    external_subscription_id: SUB,
    external_customer_id: CTM,
    external_price_id: PRI,
    expected_webhook_watermark: null,
    expected_provider_state_version: null,
    expected_linkage_fingerprint: LINK_FP,
    expected_local_state_fingerprint: "local_fp",
    ...overrides,
  };
}

function paddleSuccess(
  overrides: Record<string, unknown> = {},
): PaddleGetSubscriptionResult {
  return {
    kind: "success",
    data: {
      id: SUB,
      customer_id: CTM,
      status: "active",
      updated_at: UPDATED,
      current_billing_period: {
        starts_at: PERIOD_START,
        ends_at: PERIOD_END,
      },
      items: [{ price: { id: PRI } }],
      canceled_at: null,
      scheduled_change: null,
      ...overrides,
    },
  };
}

interface Harness {
  deps: HandlerDeps;
  prepareCalls: Array<{ company_id: string; actor_user_id: string }>;
  applyCalls: ApplyBillingReconciliationArgs[];
  finalizerCalls: RecordBillingReconciliationArgs[];
  paddleGetCalls: string[];
  authTokens: string[];
}

function makeHarness(opts: {
  authUserId?: string | null;
  prepare?:
    | PrepareBillingReconciliationResult
    | (() => Promise<PrepareBillingReconciliationResult>);
  prepareError?: Error;
  paddle?:
    | PaddleGetSubscriptionResult
    | ((id: string) => Promise<PaddleGetSubscriptionResult>);
  apply?:
    | ApplyBillingReconciliationResult
    | ((
      args: ApplyBillingReconciliationArgs,
    ) => Promise<ApplyBillingReconciliationResult>);
  finalizer?:
    | RecordBillingReconciliationResult
    | ((
      args: RecordBillingReconciliationArgs,
    ) => Promise<RecordBillingReconciliationResult>);
  corsAllowlist?: string[];
  paddleKey?: string | null;
}): Harness {
  const prepareCalls: Harness["prepareCalls"] = [];
  const applyCalls: ApplyBillingReconciliationArgs[] = [];
  const finalizerCalls: RecordBillingReconciliationArgs[] = [];
  const paddleGetCalls: string[] = [];
  const authTokens: string[] = [];

  const authLookup: AuthUserLookup = async (token) => {
    authTokens.push(token);
    if (opts.authUserId === null) return null;
    return { id: opts.authUserId ?? ACTOR };
  };

  const rpc: BillingReconciliationRpcClient = {
    async prepareCompanyBillingReconciliationServer(args) {
      prepareCalls.push(args);
      if (opts.prepareError) throw opts.prepareError;
      if (typeof opts.prepare === "function") return await opts.prepare();
      return opts.prepare ?? prepareRow();
    },
    async applyCompanyBillingReconciliationServer(args) {
      applyCalls.push(args);
      if (typeof opts.apply === "function") return await opts.apply(args);
      return opts.apply ?? {
        result: "updated",
        company_id: COMPANY,
        provider_updated_at: UPDATED,
      };
    },
    async recordCompanyBillingReconciliationResultServer(args) {
      finalizerCalls.push(args);
      if (typeof opts.finalizer === "function") {
        return await opts.finalizer(args);
      }
      return opts.finalizer ?? {
        result: args.result,
        company_id: COMPANY,
        recorded: true,
      };
    },
  };

  const deps: HandlerDeps = {
    fetch: async () => {
      throw new Error("network must not be used in tests");
    },
    clock: () => new Date("2026-09-14T12:00:00.000Z"),
    uuid: () => CORRELATION,
    authLookup,
    rpc,
    paddle: {
      async getSubscription(id) {
        paddleGetCalls.push(id);
        if (typeof opts.paddle === "function") return await opts.paddle(id);
        return opts.paddle ?? paddleSuccess();
      },
    },
    corsAllowlist: opts.corsAllowlist ?? ["https://app.example"],
    env: (k) => {
      if (k === "PADDLE_SANDBOX_API_KEY") {
        return opts.paddleKey === null ? undefined : (opts.paddleKey ?? "k");
      }
      return undefined;
    },
  };

  return {
    deps,
    prepareCalls,
    applyCalls,
    finalizerCalls,
    paddleGetCalls,
    authTokens,
  };
}

function postJson(
  body: unknown,
  init: {
    auth?: string | null;
    origin?: string | null;
    contentType?: string | null;
  } = {},
): Request {
  const headers = new Headers();
  if (init.auth !== null) {
    headers.set("Authorization", init.auth ?? `Bearer valid-token`);
  }
  if (init.origin !== null) {
    headers.set("Origin", init.origin ?? "https://app.example");
  }
  if (init.contentType !== null) {
    headers.set(
      "Content-Type",
      init.contentType ?? "application/json",
    );
  }
  return new Request("http://localhost/billing-reconciliation-paddle", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function readJson(res: Response): Promise<Record<string, unknown>> {
  return await res.json() as Record<string, unknown>;
}

function assertCallBounds(h: Harness, expected: {
  prepare?: number;
  paddle?: number;
  apply?: number;
  finalizer?: number;
}) {
  assertEquals(h.prepareCalls.length, expected.prepare ?? 0);
  assertEquals(h.paddleGetCalls.length, expected.paddle ?? 0);
  assertEquals(h.applyCalls.length, expected.apply ?? 0);
  assertEquals(h.finalizerCalls.length, expected.finalizer ?? 0);
  assertEquals(h.prepareCalls.length <= 1, true);
  assertEquals(h.paddleGetCalls.length <= 1, true);
  assertEquals(h.applyCalls.length <= 1, true);
  assertEquals(h.finalizerCalls.length <= 1, true);
}

// ---------------------------------------------------------------------------
// AUTH / REQUEST
// ---------------------------------------------------------------------------

Deno.test("OPTIONS returns 204", async () => {
  const h = makeHarness({});
  const handler = createHandler(h.deps);
  const res = await handler(
    new Request("http://localhost/x", {
      method: "OPTIONS",
      headers: { Origin: "https://app.example" },
    }),
  );
  assertEquals(res.status, 204);
  assertCallBounds(h, {});
});

Deno.test("method GET returns 405", async () => {
  const h = makeHarness({});
  const handler = createHandler(h.deps);
  const res = await handler(
    new Request("http://localhost/x", { method: "GET" }),
  );
  assertEquals(res.status, 405);
  assertCallBounds(h, {});
});

Deno.test("missing JWT returns 401; no prepare/paddle", async () => {
  const h = makeHarness({});
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }, { auth: null }));
  assertEquals(res.status, 401);
  const body = await readJson(res);
  assertEquals(body.error_code, "ATLAS_NOT_AUTHENTICATED");
  assertCallBounds(h, {});
});

Deno.test("invalid JWT returns 401; no prepare/paddle", async () => {
  const h = makeHarness({ authUserId: null });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 401);
  assertCallBounds(h, {});
});

Deno.test("malformed body / missing / invalid company_id", async () => {
  const cases: Array<{ body: unknown; status: number; code: string }> = [
    { body: "{", status: 400, code: "ATLAS_INVALID_JSON" },
    { body: {}, status: 400, code: "ATLAS_COMPANY_ID_REQUIRED" },
    {
      body: { company_id: "not-a-uuid" },
      status: 400,
      code: "ATLAS_INVALID_REQUEST",
    },
  ];
  for (const c of cases) {
    const h = makeHarness({});
    const handler = createHandler(h.deps);
    const res = await handler(postJson(c.body));
    assertEquals(res.status, c.status);
    const body = await readJson(res);
    assertEquals(body.error_code, c.code);
    assertCallBounds(h, {});
  }
});

Deno.test("forbidden actor/provider fields rejected; no RPC", async () => {
  const forbiddenBodies = [
    { company_id: COMPANY, actor_user_id: OTHER_ACTOR },
    { company_id: COMPANY, user_id: OTHER_ACTOR },
    { company_id: COMPANY, external_subscription_id: SUB },
    { company_id: COMPANY, external_customer_id: CTM },
    { company_id: COMPANY, external_price_id: PRI },
    { company_id: COMPANY, status: "active" },
  ];
  for (const body of forbiddenBodies) {
    const h = makeHarness({});
    const handler = createHandler(h.deps);
    const res = await handler(postJson(body));
    assertEquals(res.status, 400);
    assertCallBounds(h, {});
  }
});

Deno.test("actor comes from auth token not body", async () => {
  const h = makeHarness({ authUserId: ACTOR });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 200);
  assertEquals(h.authTokens, ["valid-token"]);
  assertEquals(h.prepareCalls[0]?.actor_user_id, ACTOR);
  assertCallBounds(h, { prepare: 1, paddle: 1, apply: 1, finalizer: 0 });
});

// ---------------------------------------------------------------------------
// PREPARE
// ---------------------------------------------------------------------------

Deno.test("prepare owner success then apply", async () => {
  const h = makeHarness({});
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 200);
  const body = await readJson(res);
  assertEquals(body.ok, true);
  const data = body.data as Record<string, unknown>;
  assertEquals(data.result, "updated");
  assertEquals(data.company_id, COMPANY);
  assertEquals("linkage" in data, false);
  assertEquals("expected_linkage_fingerprint" in (body as object), false);
  assertCallBounds(h, { prepare: 1, paddle: 1, apply: 1, finalizer: 0 });
});

Deno.test("prepare ATLAS_NOT_COMPANY_OWNER; no paddle", async () => {
  const { AtlasHttpError } = await import("../_shared/errors.ts");
  const h = makeHarness({
    prepareError: new AtlasHttpError(
      403,
      "ATLAS_NOT_COMPANY_OWNER",
      "Not a company owner",
    ),
  });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 403);
  assertCallBounds(h, { prepare: 1, paddle: 0, apply: 0, finalizer: 0 });
});

Deno.test("prepare unlinked; no paddle", async () => {
  const { AtlasHttpError } = await import("../_shared/errors.ts");
  const h = makeHarness({
    prepareError: new AtlasHttpError(
      409,
      "ATLAS_BILLING_RECONCILIATION_UNLINKED",
      "Billing is not linked for reconciliation",
    ),
  });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 409);
  assertCallBounds(h, { prepare: 1, paddle: 0, apply: 0, finalizer: 0 });
});

Deno.test("prepare generic failure; no paddle/finalizer", async () => {
  const { AtlasHttpError } = await import("../_shared/errors.ts");
  const h = makeHarness({
    prepareError: new AtlasHttpError(
      500,
      "ATLAS_INTERNAL_ERROR",
      "Internal error",
    ),
  });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 500);
  assertCallBounds(h, { prepare: 1, paddle: 0, apply: 0, finalizer: 0 });
});

// ---------------------------------------------------------------------------
// PROVIDER + FINALIZER
// ---------------------------------------------------------------------------

Deno.test("exact prepare subscription id used in GET", async () => {
  const h = makeHarness({
    prepare: prepareRow({
      external_subscription_id: "sub_01h4examplesubid0000000099",
    }),
    paddle: async (id) => {
      assertEquals(id, "sub_01h4examplesubid0000000099");
      return {
        kind: "not_found",
        sanitized_message: "missing",
      };
    },
  });
  const handler = createHandler(h.deps);
  await handler(postJson({ company_id: COMPANY }));
  assertEquals(h.paddleGetCalls, ["sub_01h4examplesubid0000000099"]);
  assertCallBounds(h, { prepare: 1, paddle: 1, apply: 0, finalizer: 1 });
});

Deno.test("404 → finalizer not_found; apply=0", async () => {
  const h = makeHarness({
    paddle: { kind: "not_found", sanitized_message: "gone" },
  });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 404);
  assertEquals(h.finalizerCalls[0]?.result, "not_found");
  assertEquals(h.finalizerCalls[0]?.expected_external_subscription_id, SUB);
  assertEquals(h.finalizerCalls[0]?.expected_external_customer_id, CTM);
  assertEquals(h.finalizerCalls[0]?.expected_linkage_fingerprint, LINK_FP);
  assertEquals(h.finalizerCalls[0]?.provider_updated_at, null);
  assertEquals(
    (h.finalizerCalls[0]?.error_sanitized ?? "").length <= 200,
    true,
  );
  assertCallBounds(h, { prepare: 1, paddle: 1, apply: 0, finalizer: 1 });
});

Deno.test("timeout/network/500 → finalizer provider_error", async () => {
  const cases: PaddleGetSubscriptionResult[] = [
    {
      kind: "provider_error",
      reason: "timeout",
      sanitized_message: "timed out",
    },
    {
      kind: "provider_error",
      reason: "network",
      sanitized_message: "network",
    },
    {
      kind: "provider_error",
      reason: "http_5xx",
      sanitized_message: "boom",
    },
  ];
  for (const paddle of cases) {
    const h = makeHarness({ paddle });
    const handler = createHandler(h.deps);
    const res = await handler(postJson({ company_id: COMPANY }));
    assertEquals(res.status, 502);
    assertEquals(h.finalizerCalls[0]?.result, "provider_error");
    assertCallBounds(h, { prepare: 1, paddle: 1, apply: 0, finalizer: 1 });
  }
});

Deno.test("malformed 2xx → finalizer invalid_provider_response", async () => {
  const h = makeHarness({
    paddle: {
      kind: "invalid_provider_response",
      sanitized_message: "bad json",
    },
  });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 502);
  assertEquals(h.finalizerCalls[0]?.result, "invalid_provider_response");
  assertCallBounds(h, { prepare: 1, paddle: 1, apply: 0, finalizer: 1 });
});

Deno.test("mismatched subscription/customer → invalid_provider_response", async () => {
  const mismatchCases = [
    paddleSuccess({ id: "sub_01h4examplesubid0000000099" }),
    paddleSuccess({ customer_id: "ctm_01h4examplecustid000000099" }),
  ];
  for (const paddle of mismatchCases) {
    const h = makeHarness({ paddle });
    const handler = createHandler(h.deps);
    const res = await handler(postJson({ company_id: COMPANY }));
    assertEquals(res.status, 502);
    assertEquals(h.finalizerCalls[0]?.result, "invalid_provider_response");
    assertCallBounds(h, { prepare: 1, paddle: 1, apply: 0, finalizer: 1 });
  }
});

Deno.test("finalizer server-derived busy/unlinked/stale_snapshot respected", async () => {
  const derived: Array<{
    requested: ReconciliationFinalizerResult;
    returned: string;
    status: number;
  }> = [
    { requested: "not_found", returned: "busy", status: 409 },
    { requested: "provider_error", returned: "unlinked", status: 409 },
    {
      requested: "invalid_provider_response",
      returned: "stale_snapshot",
      status: 409,
    },
  ];
  for (const d of derived) {
    const h = makeHarness({
      paddle: { kind: "not_found", sanitized_message: "x" },
      finalizer: {
        result: d.returned,
        company_id: COMPANY,
        recorded: d.returned !== "busy",
      },
    });
    // force requested path via paddle kind matching first case only — override:
    h.deps.paddle.getSubscription = async () => {
      h.paddleGetCalls.push(SUB);
      if (d.requested === "not_found") {
        return { kind: "not_found", sanitized_message: "x" };
      }
      if (d.requested === "provider_error") {
        return {
          kind: "provider_error",
          reason: "network",
          sanitized_message: "x",
        };
      }
      return {
        kind: "invalid_provider_response",
        sanitized_message: "x",
      };
    };
    const handler = createHandler(h.deps);
    const res = await handler(postJson({ company_id: COMPANY }));
    assertEquals(res.status, d.status);
    const body = await readJson(res);
    assertEquals(
      body.error_code,
      d.returned === "busy"
        ? "ATLAS_BILLING_RECONCILIATION_BUSY"
        : d.returned === "unlinked"
        ? "ATLAS_BILLING_RECONCILIATION_UNLINKED"
        : "ATLAS_BILLING_RECONCILIATION_STALE_SNAPSHOT",
    );
    assertEquals(h.finalizerCalls.length, 1);
    assertEquals(h.applyCalls.length, 0);
  }
});

// ---------------------------------------------------------------------------
// APPLY
// ---------------------------------------------------------------------------

Deno.test("valid statuses apply once", async () => {
  for (
    const status of ["active", "past_due", "paused", "canceled", "trialing"]
  ) {
    const h = makeHarness({
      paddle: paddleSuccess({
        status,
        canceled_at: status === "canceled" ? UPDATED : null,
      }),
      apply: {
        result: status === "trialing" ? "unsupported_state" : "updated",
        company_id: COMPANY,
        provider_updated_at: UPDATED,
      },
    });
    const handler = createHandler(h.deps);
    const res = await handler(postJson({ company_id: COMPANY }));
    if (status === "trialing") {
      assertEquals(res.status, 409);
      const body = await readJson(res);
      assertEquals(
        body.error_code,
        "ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_STATE",
      );
    } else {
      assertEquals(res.status, 200);
    }
    assertEquals(h.applyCalls[0]?.provider_subscription_status, status);
    assertCallBounds(h, { prepare: 1, paddle: 1, apply: 1, finalizer: 0 });
  }
});

Deno.test("apply outcome mapping matrix", async () => {
  const cases: Array<{ result: string; status: number; code?: string }> = [
    { result: "updated", status: 200 },
    { result: "in_sync", status: 200 },
    {
      result: "stale_provider_state",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_STALE_PROVIDER_STATE",
    },
    {
      result: "busy",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_BUSY",
    },
    {
      result: "conflict",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_CONFLICT",
    },
    {
      result: "unlinked",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_UNLINKED",
    },
    {
      result: "stale_snapshot",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_STALE_SNAPSHOT",
    },
    {
      result: "catalog_mismatch",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_CATALOG_MISMATCH",
    },
    {
      result: "unsupported_state",
      status: 409,
      code: "ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_STATE",
    },
    {
      result: "invalid_provider_response",
      status: 502,
      code: "ATLAS_BILLING_RECONCILIATION_INVALID_PROVIDER_RESPONSE",
    },
    { result: "totally_unknown", status: 500, code: "ATLAS_INTERNAL_ERROR" },
  ];
  for (const c of cases) {
    const h = makeHarness({
      apply: {
        result: c.result,
        company_id: COMPANY,
        provider_updated_at: UPDATED,
      },
    });
    const handler = createHandler(h.deps);
    const res = await handler(postJson({ company_id: COMPANY }));
    assertEquals(res.status, c.status, c.result);
    if (c.code) {
      const body = await readJson(res);
      assertEquals(body.error_code, c.code);
    }
    assertCallBounds(h, { prepare: 1, paddle: 1, apply: 1, finalizer: 0 });
  }
});

// ---------------------------------------------------------------------------
// SECURITY
// ---------------------------------------------------------------------------

Deno.test("success response never leaks raw provider/supabase secrets", async () => {
  const h = makeHarness({});
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  const text = await res.text();
  assertEquals(text.includes("Bearer"), false);
  assertEquals(text.includes(LINK_FP), false);
  assertEquals(text.includes("local_fp"), false);
  assertEquals(text.includes("items"), false);
  assertEquals(text.includes("current_billing_period"), false);
  assertEquals(text.includes("PADDLE"), false);
  const body = JSON.parse(text) as Record<string, unknown>;
  const data = body.data as Record<string, unknown>;
  assertEquals(Object.keys(data).sort(), [
    "company_id",
    "provider_updated_at",
    "result",
  ]);
});

Deno.test("missing paddle key → 503; no prepare", async () => {
  const h = makeHarness({ paddleKey: null });
  const handler = createHandler(h.deps);
  const res = await handler(postJson({ company_id: COMPANY }));
  assertEquals(res.status, 503);
  assertCallBounds(h, {});
});
