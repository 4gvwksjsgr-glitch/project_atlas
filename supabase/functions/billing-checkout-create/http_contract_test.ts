// deno-lint-ignore-file require-await
/**
 * HTTP contract tests: methods, content-type, body limit, UUID, idempotency, CORS, OPTIONS.
 */

import { assertEquals, assertRejects } from "@std/assert";
import { AtlasHttpError } from "../_shared/errors.ts";
import {
  assertPostOrOptions,
  buildOptionsResponse,
  decideCors,
  MAX_BODY_BYTES,
  parseCheckoutCreateBody,
  parseCorsAllowlist,
  readBodyWithLimit,
  requireIdempotencyKey,
  requireJsonContentType,
} from "../_shared/http.ts";
import { handleCheckoutCreate } from "./handler.ts";
import type { HandlerDeps, ReserveBillingCheckoutSessionRow } from "./types.ts";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const ACTOR = "22222222-2222-4222-8222-222222222222";
const CORRELATION = "33333333-3333-4333-8333-333333333333";

function baseReservation(
  overrides: Partial<ReserveBillingCheckoutSessionRow> = {},
): ReserveBillingCheckoutSessionRow {
  return {
    session_id: "44444444-4444-4444-8444-444444444444",
    reuse: false,
    provider_environment: "test",
    billing_provider_price_id: "55555555-5555-4555-8555-555555555555",
    external_price_id: "pri_01testprice00000000000001",
    atlas_plan_code: "premium",
    offer_code: "premium_monthly",
    checkout_status: "created",
    provider_create_status: "created",
    return_token_plain: "rtok_test_plain_value",
    return_token_version: 1,
    expires_at: "2026-08-05T00:00:00.000Z",
    existing_checkout_url:
      "https://atlas.example/billing/checkout?_ptxn=txn_01abcdefghijklmnopqr",
    existing_external_transaction_id: "txn_01abcdefghijklmnopqr",
    provider_code: "paddle",
    payment_page_origin: "https://atlas.example",
    checkout_path: "/billing/checkout",
    return_path: "/billing/return",
    checkout_page_url: "https://atlas.example/billing/checkout",
    ...overrides,
  };
}

function deps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    fetch: async () => {
      throw new Error("network should not be called");
    },
    clock: () => new Date("2026-08-04T12:00:00.000Z"),
    uuid: () => CORRELATION,
    authLookup: async () => ({ id: ACTOR }),
    rpc: {
      reserveBillingCheckoutSessionServer: async () => baseReservation(),
      attachBillingCheckoutProviderResultServer: async () => ({
        applied: true,
        session_id: "44444444-4444-4444-8444-444444444444",
        provider_create_status: "processing",
        checkout_status: "created",
      }),
    },
    paddle: {
      createCheckout: async () => {
        throw new Error("paddle should not be called");
      },
    },
    corsAllowlist: ["https://app.atlas.example"],
    env: (key: string) =>
      key === "PADDLE_SANDBOX_API_KEY" ? "test-sandbox-key" : undefined,
    ...overrides,
  };
}

Deno.test("assertPostOrOptions allows OPTIONS and POST only", () => {
  assertEquals(assertPostOrOptions("OPTIONS"), "OPTIONS");
  assertEquals(assertPostOrOptions("POST"), "POST");
  assertEquals(assertPostOrOptions("post"), "POST");
});

Deno.test("assertPostOrOptions rejects GET with 405", () => {
  try {
    assertPostOrOptions("GET");
    throw new Error("expected throw");
  } catch (e) {
    assertEquals(e instanceof AtlasHttpError, true);
    assertEquals((e as AtlasHttpError).status, 405);
    assertEquals((e as AtlasHttpError).errorCode, "ATLAS_METHOD_NOT_ALLOWED");
  }
});

Deno.test("requireJsonContentType accepts application/json", () => {
  requireJsonContentType("application/json");
  requireJsonContentType("application/json; charset=utf-8");
});

Deno.test("requireJsonContentType rejects other types", () => {
  try {
    requireJsonContentType("text/plain");
    throw new Error("expected throw");
  } catch (e) {
    assertEquals((e as AtlasHttpError).errorCode, "ATLAS_INVALID_CONTENT_TYPE");
  }
});

Deno.test("readBodyWithLimit enforces 4 KiB without Content-Length", async () => {
  const oversized = new Uint8Array(MAX_BODY_BYTES + 1).fill(0x61);
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(oversized);
      controller.close();
    },
  });
  const req = new Request("http://local/fn", {
    method: "POST",
    body: stream,
    // intentionally no content-length
  });
  await assertRejects(
    () => readBodyWithLimit(req),
    AtlasHttpError,
  );
});

Deno.test("readBodyWithLimit accepts body at limit", async () => {
  const ok = new Uint8Array(MAX_BODY_BYTES).fill(0x62);
  const req = new Request("http://local/fn", {
    method: "POST",
    body: ok,
  });
  const bytes = await readBodyWithLimit(req);
  assertEquals(bytes.byteLength, MAX_BODY_BYTES);
});

Deno.test("parseCheckoutCreateBody requires strict UUID company_id", () => {
  const enc = new TextEncoder();
  const ok = parseCheckoutCreateBody(
    enc.encode(JSON.stringify({ company_id: COMPANY })),
  );
  assertEquals(ok.company_id, COMPANY);

  try {
    parseCheckoutCreateBody(enc.encode(JSON.stringify({ company_id: "nope" })));
    throw new Error("expected throw");
  } catch (e) {
    assertEquals((e as AtlasHttpError).errorCode, "ATLAS_INVALID_REQUEST");
  }
});

Deno.test("parseCheckoutCreateBody rejects commerce and actor fields", () => {
  const enc = new TextEncoder();
  const cases = [
    { company_id: COMPANY, offer: "premium_monthly" },
    { company_id: COMPANY, plan: "premium" },
    { company_id: COMPANY, price: "x" },
    { company_id: COMPANY, amount: 1 },
    { company_id: COMPANY, currency: "EUR" },
    { company_id: COMPANY, environment: "test" },
    { company_id: COMPANY, actor: ACTOR },
    { company_id: COMPANY, actor_user_id: ACTOR },
    { company_id: COMPANY, user_id: ACTOR },
  ];
  for (const body of cases) {
    try {
      parseCheckoutCreateBody(enc.encode(JSON.stringify(body)));
      throw new Error(`expected throw for ${JSON.stringify(body)}`);
    } catch (e) {
      assertEquals(e instanceof AtlasHttpError, true);
      assertEquals((e as AtlasHttpError).errorCode, "ATLAS_INVALID_REQUEST");
    }
  }
});

Deno.test("requireIdempotencyKey opaque max 128; rejects control chars", () => {
  assertEquals(requireIdempotencyKey("  abc-123  "), "abc-123");
  assertEquals(requireIdempotencyKey("a".repeat(128)), "a".repeat(128));
  try {
    requireIdempotencyKey(null);
    throw new Error("expected");
  } catch (e) {
    assertEquals(
      (e as AtlasHttpError).errorCode,
      "ATLAS_IDEMPOTENCY_KEY_REQUIRED",
    );
  }
  try {
    requireIdempotencyKey("   ");
    throw new Error("expected");
  } catch (e) {
    assertEquals(
      (e as AtlasHttpError).errorCode,
      "ATLAS_IDEMPOTENCY_KEY_REQUIRED",
    );
  }
  try {
    requireIdempotencyKey("a".repeat(129));
    throw new Error("expected");
  } catch (e) {
    assertEquals(
      (e as AtlasHttpError).errorCode,
      "ATLAS_INVALID_IDEMPOTENCY_KEY",
    );
  }
  for (const bad of ["ab\rcd", "ab\ncd", "ab\tcd", "ab\0cd", "\nabc"]) {
    try {
      requireIdempotencyKey(bad);
      throw new Error(`expected throw for ${JSON.stringify(bad)}`);
    } catch (e) {
      assertEquals(
        (e as AtlasHttpError).errorCode,
        "ATLAS_INVALID_IDEMPOTENCY_KEY",
      );
    }
  }
});

Deno.test("CORS allowlist never star; native no-Origin ok", () => {
  assertEquals(parseCorsAllowlist("*, https://a.example"), [
    "https://a.example",
  ]);
  const native = decideCors(null, ["https://a.example"]);
  assertEquals(native.ok, true);
  assertEquals(native.hasAllowedOrigin, false);

  const denied = decideCors("https://evil.example", ["https://a.example"]);
  assertEquals(denied.ok, false);

  const allowed = decideCors("https://a.example", ["https://a.example"]);
  assertEquals(allowed.ok, true);
  assertEquals(allowed.allowOrigin, "https://a.example");
});

Deno.test("OPTIONS is deterministic and denies unknown origin", async () => {
  const deny = buildOptionsResponse(
    "https://evil.example",
    ["https://app.atlas.example"],
    CORRELATION,
  );
  assertEquals(deny.status, 403);
  const denyBody = await deny.json();
  assertEquals(denyBody.error_code, "ATLAS_CORS_ORIGIN_DENIED");
  assertEquals(denyBody.correlation_id, CORRELATION);
  assertEquals(deny.headers.get("Access-Control-Allow-Origin"), null);

  const ok = buildOptionsResponse(
    "https://app.atlas.example",
    ["https://app.atlas.example"],
    CORRELATION,
  );
  assertEquals(ok.status, 204);
  assertEquals(
    ok.headers.get("Access-Control-Allow-Origin"),
    "https://app.atlas.example",
  );
  assertEquals(ok.headers.get("Access-Control-Allow-Methods"), "POST, OPTIONS");
  assertEquals(ok.headers.get("Access-Control-Allow-Origin") === "*", false);
});

Deno.test("handler OPTIONS path via handleCheckoutCreate", async () => {
  const res = await handleCheckoutCreate(
    new Request("http://local/billing-checkout-create", { method: "OPTIONS" }),
    deps(),
  );
  assertEquals(res.status, 204);
});

Deno.test("handler GET returns 405 with Allow header", async () => {
  const res = await handleCheckoutCreate(
    new Request("http://local/billing-checkout-create", { method: "GET" }),
    deps(),
  );
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("Allow"), "OPTIONS, POST");
  const body = await res.json();
  assertEquals(body.schema_version, 1);
  assertEquals(body.error_code, "ATLAS_METHOD_NOT_ALLOWED");
  assertEquals(body.correlation_id, CORRELATION);
  assertEquals(typeof body.retryable, "boolean");
});

Deno.test("handler POST missing Idempotency-Key", async () => {
  const res = await handleCheckoutCreate(
    new Request("http://local/billing-checkout-create", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer fake",
      },
      body: JSON.stringify({ company_id: COMPANY }),
    }),
    deps(),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_IDEMPOTENCY_KEY_REQUIRED");
});

Deno.test("handler POST native without Origin succeeds when JWT valid", async () => {
  const res = await handleCheckoutCreate(
    new Request("http://local/billing-checkout-create", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer fake",
        "Idempotency-Key": "idem-native-1",
      },
      body: JSON.stringify({ company_id: COMPANY }),
    }),
    deps(),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.schema_version, 1);
  assertEquals(body.reused, true);
  assertEquals(body.return_token_version, 1);
  // ensure success shape; do not log token in assertions beyond equality
  assertEquals(typeof body.return_token, "string");
});

Deno.test("missing Paddle API key: no reserve/attach/paddle", async () => {
  let reserveCalls = 0;
  let attachCalls = 0;
  let paddleCalls = 0;
  const res = await handleCheckoutCreate(
    new Request("http://local/billing-checkout-create", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer fake",
        "Idempotency-Key": "idem-missing-key",
        "Origin": "https://app.atlas.example",
      },
      body: JSON.stringify({ company_id: COMPANY }),
    }),
    deps({
      env: () => undefined,
      rpc: {
        reserveBillingCheckoutSessionServer: async () => {
          reserveCalls += 1;
          return baseReservation();
        },
        attachBillingCheckoutProviderResultServer: async () => {
          attachCalls += 1;
          return {
            applied: true,
            session_id: "44444444-4444-4444-8444-444444444444",
            provider_create_status: "processing",
            checkout_status: "created",
          };
        },
      },
      paddle: {
        createCheckout: async () => {
          paddleCalls += 1;
          throw new Error("should not call");
        },
      },
    }),
  );
  assertEquals(res.status, 503);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_CHECKOUT_UNAVAILABLE");
  assertEquals(body.retryable, false);
  assertEquals(JSON.stringify(body).includes("test-sandbox"), false);
  assertEquals(reserveCalls, 0);
  assertEquals(attachCalls, 0);
  assertEquals(paddleCalls, 0);
});
