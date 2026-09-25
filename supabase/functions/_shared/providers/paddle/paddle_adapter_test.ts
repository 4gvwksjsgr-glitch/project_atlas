// deno-lint-ignore-file require-await
/**
 * Paddle sandbox adapter tests — injected fake fetch only.
 */

import { assertEquals } from "@std/assert";
import {
  createPaddleSandboxCheckoutAdapter,
  createPaddleSandboxSubscriptionReader,
  getPaddleSandboxSubscription,
  isValidPaddleTransactionId,
  previewPaddleSandboxSubscriptionNextBilledAt,
  readResponseBodyWithLimit,
  updatePaddleSandboxSubscriptionNextBilledAt,
  validatePaddleCheckoutUrl,
} from "./paddle_adapter.ts";
import {
  PADDLE_MAX_RESPONSE_BYTES,
  PADDLE_SANDBOX_BASE_URL,
  type PaddleCreateCheckoutInput,
  type PaddleUpdateNextBilledAtInput,
} from "./paddle_types.ts";

const TXN = "txn_01h4exampletxnid000000abc";
const ORIGIN = "https://atlas.example";
const PATH = "/billing/checkout";
const PAGE = `${ORIGIN}${PATH}`;
const CHECKOUT_URL = `${PAGE}?_ptxn=${TXN}`;

const input: PaddleCreateCheckoutInput = {
  external_price_id: "pri_01testprice00000000000001",
  checkout_page_url: PAGE,
  payment_page_origin: ORIGIN,
  checkout_path: PATH,
  company_id: "11111111-1111-4111-8111-111111111111",
  checkout_session_id: "44444444-4444-4444-8444-444444444444",
  offer_code: "premium_monthly",
};

Deno.test("isValidPaddleTransactionId accepts txn_ alphanumeric", () => {
  assertEquals(isValidPaddleTransactionId(TXN), true);
  assertEquals(isValidPaddleTransactionId("txn_ABC123"), true);
  assertEquals(isValidPaddleTransactionId("sub_01abc"), false);
  assertEquals(isValidPaddleTransactionId("txn_"), false);
});

Deno.test("validatePaddleCheckoutUrl enforces https origin path _ptxn", () => {
  assertEquals(
    validatePaddleCheckoutUrl(CHECKOUT_URL, ORIGIN, PATH, TXN),
    true,
  );
  assertEquals(
    validatePaddleCheckoutUrl(
      `http://atlas.example${PATH}?_ptxn=${TXN}`,
      ORIGIN,
      PATH,
      TXN,
    ),
    false,
  );
  assertEquals(
    validatePaddleCheckoutUrl(
      `${CHECKOUT_URL}#frag`,
      ORIGIN,
      PATH,
      TXN,
    ),
    false,
  );
  assertEquals(
    validatePaddleCheckoutUrl(
      `https://user:pass@atlas.example${PATH}?_ptxn=${TXN}`,
      ORIGIN,
      PATH,
      TXN,
    ),
    false,
  );
  assertEquals(
    validatePaddleCheckoutUrl(
      `${PAGE}?_ptxn=txn_other`,
      ORIGIN,
      PATH,
      TXN,
    ),
    false,
  );
  assertEquals(
    validatePaddleCheckoutUrl(
      `https://evil.example${PATH}?_ptxn=${TXN}`,
      ORIGIN,
      PATH,
      TXN,
    ),
    false,
  );
});

Deno.test("createCheckout posts to sandbox with bearer and custom_data", async () => {
  let seenUrl = "";
  let seenAuth = "";
  let seenVersion = "";
  let seenBody: Record<string, unknown> = {};

  const adapter = createPaddleSandboxCheckoutAdapter({
    env: (k) => k === "PADDLE_SANDBOX_API_KEY" ? "test-sandbox-key" : undefined,
    fetch: async (url, init) => {
      seenUrl = String(url);
      const opts = (init ?? {}) as RequestInit;
      const headers = new Headers(opts.headers);
      seenAuth = headers.get("Authorization") ?? "";
      seenVersion = headers.get("Paddle-Version") ?? "";
      seenBody = JSON.parse(String(opts.body));
      return new Response(
        JSON.stringify({
          data: {
            id: TXN,
            checkout: { url: CHECKOUT_URL },
          },
        }),
        { status: 201, headers: { "Content-Type": "application/json" } },
      );
    },
  });

  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "success");
  if (result.kind === "success") {
    assertEquals(result.external_transaction_id, TXN);
    assertEquals(result.checkout_url, CHECKOUT_URL);
  }
  assertEquals(seenUrl, `${PADDLE_SANDBOX_BASE_URL}/transactions`);
  assertEquals(seenAuth, "Bearer test-sandbox-key");
  assertEquals(seenVersion, "1");
  assertEquals(seenBody.checkout, { url: PAGE });
  const items = seenBody.items as Array<{ price_id: string; quantity: number }>;
  assertEquals(items[0], {
    price_id: input.external_price_id,
    quantity: 1,
  });
  const custom = seenBody.custom_data as Record<string, unknown>;
  assertEquals(custom.atlas_schema_version, 1);
  assertEquals(custom.atlas_company_id, input.company_id);
  assertEquals(custom.atlas_checkout_session_id, input.checkout_session_id);
  assertEquals(custom.atlas_offer_code, "premium_monthly");
  assertEquals("return_token" in custom, false);
  assertEquals("atlas_return_token" in custom, false);
});

Deno.test("createCheckout maps definitive whitelist 4xx only", async () => {
  for (const status of [400, 401, 403, 404, 422]) {
    const adapter = createPaddleSandboxCheckoutAdapter({
      env: () => "k",
      fetch: async () =>
        new Response(JSON.stringify({ error: { detail: "rejected" } }), {
          status,
        }),
    });
    const result = await adapter.createCheckout(input);
    assertEquals(result.kind, "definitive_client_error");
    if (result.kind === "definitive_client_error") {
      assertEquals(result.http_status, status);
    }
  }
});

Deno.test("createCheckout maps uncertain client statuses", async () => {
  for (const status of [408, 409, 425, 429, 418]) {
    const adapter = createPaddleSandboxCheckoutAdapter({
      env: () => "k",
      fetch: async () =>
        new Response(JSON.stringify({ error: { detail: "maybe" } }), {
          status,
        }),
    });
    const result = await adapter.createCheckout(input);
    assertEquals(result.kind, "uncertain", `status ${status}`);
  }
});

Deno.test("createCheckout maps 5xx to uncertain", async () => {
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () =>
      new Response(JSON.stringify({ error: { detail: "boom" } }), {
        status: 503,
      }),
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") {
    assertEquals(result.reason, "http_5xx");
  }
});

Deno.test("createCheckout maps network failure to uncertain", async () => {
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () => {
      throw new TypeError("network down");
    },
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") {
    assertEquals(result.reason, "network");
  }
});

Deno.test("createCheckout maps abort to timeout", async () => {
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () => {
      const err = new Error("The signal has been aborted");
      err.name = "AbortError";
      throw err;
    },
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") {
    assertEquals(result.reason, "timeout");
  }
});

Deno.test("createCheckout rejects invalid checkout url from paddle", async () => {
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () =>
      new Response(
        JSON.stringify({
          data: {
            id: TXN,
            checkout: { url: "https://evil.example/pay?_ptxn=" + TXN },
          },
        }),
        { status: 201 },
      ),
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") {
    assertEquals(result.reason, "invalid_checkout_url");
  }
});

Deno.test("createCheckout without API key is uncertain", async () => {
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => undefined,
    fetch: async () => {
      throw new Error("should not fetch");
    },
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
});

Deno.test("readResponseBodyWithLimit accepts body below and at limit", async () => {
  const below = new TextEncoder().encode("x".repeat(100));
  const r1 = await readResponseBodyWithLimit(
    new Response(below, { status: 200 }),
    256,
  );
  assertEquals(r1.ok, true);
  if (r1.ok) assertEquals(r1.bytes.byteLength, 100);

  const at = new TextEncoder().encode("y".repeat(256));
  const r2 = await readResponseBodyWithLimit(
    new Response(at, { status: 200 }),
    256,
  );
  assertEquals(r2.ok, true);
  if (r2.ok) assertEquals(r2.bytes.byteLength, 256);
});

Deno.test("readResponseBodyWithLimit rejects oversized body", async () => {
  const over = new TextEncoder().encode("z".repeat(257));
  const r = await readResponseBodyWithLimit(
    new Response(over, { status: 200 }),
    256,
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "oversized");
});

Deno.test("readResponseBodyWithLimit enforces limit without Content-Length", async () => {
  const chunk = new TextEncoder().encode("a".repeat(200));
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(chunk);
      controller.enqueue(chunk);
      controller.close();
    },
  });
  const r = await readResponseBodyWithLimit(
    new Response(stream, { status: 200 }),
    256,
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "oversized");
});

Deno.test("readResponseBodyWithLimit rejects misleading Content-Length", async () => {
  // Header claims small; stream is large — still enforce real bytes.
  const chunk = new TextEncoder().encode("b".repeat(300));
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(chunk);
      controller.close();
    },
  });
  const r = await readResponseBodyWithLimit(
    new Response(stream, {
      status: 200,
      headers: { "Content-Length": "10" },
    }),
    256,
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "oversized");
});

Deno.test("readResponseBodyWithLimit maps stream read failure", async () => {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.error(new Error("boom"));
    },
  });
  const r = await readResponseBodyWithLimit(
    new Response(stream, { status: 200 }),
    256,
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "read_failure");
});

Deno.test("createCheckout oversized response is uncertain", async () => {
  const big = "x".repeat(PADDLE_MAX_RESPONSE_BYTES + 1);
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () =>
      new Response(big, {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }),
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
});

Deno.test("readResponseBodyWithLimit accepts exactly PADDLE_MAX_RESPONSE_BYTES", async () => {
  // Compact in-memory body at the real production limit (not oversized).
  const exact = new Uint8Array(PADDLE_MAX_RESPONSE_BYTES);
  exact.fill(0x7b); // '{' — invalid JSON as a whole, but not oversized
  const r = await readResponseBodyWithLimit(
    new Response(exact, { status: 200 }),
  );
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.bytes.byteLength, PADDLE_MAX_RESPONSE_BYTES);
  }
});

Deno.test("createCheckout at exact max body is not oversized (malformed JSON)", async () => {
  const exact = new Uint8Array(PADDLE_MAX_RESPONSE_BYTES);
  exact.fill(0x41); // 'A' — not JSON
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () =>
      new Response(exact, {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }),
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") {
    assertEquals(result.reason, "malformed_response");
    assertEquals(
      result.sanitized_message.includes("exceeded size limit"),
      false,
    );
  }
});

Deno.test("readResponseBodyWithLimit rejects PADDLE_MAX_RESPONSE_BYTES + 1", async () => {
  const first = new Uint8Array(PADDLE_MAX_RESPONSE_BYTES);
  first.fill(0x42);
  const extra = new Uint8Array([0x42]);
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(first);
      controller.enqueue(extra);
      controller.close();
    },
  });
  const r = await readResponseBodyWithLimit(
    new Response(stream, { status: 200 }),
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "oversized");
});

Deno.test("createCheckout at max+1 is oversized uncertain", async () => {
  const first = new Uint8Array(PADDLE_MAX_RESPONSE_BYTES);
  first.fill(0x42);
  const extra = new Uint8Array([0x42]);
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(first);
      controller.enqueue(extra);
      controller.close();
    },
  });
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () =>
      new Response(stream, {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }),
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") {
    assertEquals(result.reason, "malformed_response");
    assertEquals(
      result.sanitized_message,
      "Paddle response exceeded size limit",
    );
  }
  assertEquals(JSON.stringify(result).includes("BBBBBBBB"), false);
});

// ---------------------------------------------------------------------------
// GET /subscriptions/{id} — D2 reconciliation
// ---------------------------------------------------------------------------

const SUB_ID = "sub_01h4examplesubid0000000001";
const CTM_ID = "ctm_01h4examplecustid000000001";
const PRI_ID = "pri_01h4examplepriceid00000001";

function subscriptionEnvelope(overrides: Record<string, unknown> = {}) {
  return {
    data: {
      id: SUB_ID,
      customer_id: CTM_ID,
      status: "active",
      updated_at: "2026-09-14T10:00:00.000Z",
      current_billing_period: {
        starts_at: "2026-09-01T00:00:00.000Z",
        ends_at: "2026-10-01T00:00:00.000Z",
      },
      items: [{ price: { id: PRI_ID } }],
      canceled_at: null,
      scheduled_change: null,
      ...overrides,
    },
  };
}

Deno.test("getSubscription exact GET path bearer version one request", async () => {
  let calls = 0;
  let seenUrl = "";
  let seenMethod = "";
  let seenAuth = "";
  let seenVersion = "";
  let seenContentType: string | null = null;

  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: (k) => k === "PADDLE_SANDBOX_API_KEY" ? "secret-key-xyz" : undefined,
    fetch: async (url, init) => {
      calls += 1;
      seenUrl = String(url);
      const opts = (init ?? {}) as RequestInit;
      seenMethod = String(opts.method ?? "GET");
      const headers = new Headers(opts.headers);
      seenAuth = headers.get("Authorization") ?? "";
      seenVersion = headers.get("Paddle-Version") ?? "";
      seenContentType = headers.get("Content-Type");
      return new Response(JSON.stringify(subscriptionEnvelope()), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    },
  });

  assertEquals(result.kind, "success");
  assertEquals(calls, 1);
  assertEquals(
    seenUrl,
    `${PADDLE_SANDBOX_BASE_URL}/subscriptions/${encodeURIComponent(SUB_ID)}`,
  );
  assertEquals(seenMethod, "GET");
  assertEquals(seenAuth, "Bearer secret-key-xyz");
  assertEquals(seenVersion, "1");
  assertEquals(seenContentType, null);
  assertEquals(JSON.stringify(result).includes("secret-key-xyz"), false);
  assertEquals(JSON.stringify(result).includes("Bearer"), false);
});

Deno.test("getSubscription encodes exact id in path", async () => {
  const special = "sub_01h4examplesubid0000000001";
  let seenUrl = "";
  await getPaddleSandboxSubscription(special, {
    env: () => "k",
    fetch: async (url) => {
      seenUrl = String(url);
      return new Response(JSON.stringify(subscriptionEnvelope()), {
        status: 200,
      });
    },
  });
  assertEquals(
    seenUrl.endsWith(`/subscriptions/${encodeURIComponent(special)}`),
    true,
  );
  assertEquals(seenUrl.includes("?"), false);
  assertEquals(seenUrl.includes("/subscriptions?"), false);
});

Deno.test("getSubscription classifies 404 as not_found", async () => {
  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () =>
      new Response(JSON.stringify({ error: { detail: "missing" } }), {
        status: 404,
      }),
  });
  assertEquals(result.kind, "not_found");
});

Deno.test("getSubscription classifies 500 as provider_error", async () => {
  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () =>
      new Response(JSON.stringify({ error: { detail: "boom" } }), {
        status: 500,
      }),
  });
  assertEquals(result.kind, "provider_error");
  if (result.kind === "provider_error") {
    assertEquals(result.reason, "http_5xx");
  }
});

Deno.test("getSubscription classifies generic non-2xx as provider_error", async () => {
  for (const status of [400, 401, 403, 409, 418, 422, 429]) {
    const result = await getPaddleSandboxSubscription(SUB_ID, {
      env: () => "k",
      fetch: async () =>
        new Response(JSON.stringify({ error: { detail: "x" } }), { status }),
    });
    assertEquals(result.kind, "provider_error", `status ${status}`);
    if (result.kind === "provider_error") {
      assertEquals(result.reason, "http_non_2xx");
    }
  }
});

Deno.test("getSubscription classifies timeout and network", async () => {
  const timeout = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () => {
      const err = new Error("Aborted");
      err.name = "AbortError";
      throw err;
    },
  });
  assertEquals(timeout.kind, "provider_error");
  if (timeout.kind === "provider_error") {
    assertEquals(timeout.reason, "timeout");
  }

  const network = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () => {
      throw new Error("connect ECONNREFUSED");
    },
  });
  assertEquals(network.kind, "provider_error");
  if (network.kind === "provider_error") {
    assertEquals(network.reason, "network");
  }
});

Deno.test("getSubscription malformed JSON on 2xx is invalid_provider_response", async () => {
  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () => new Response("{not-json", { status: 200 }),
  });
  assertEquals(result.kind, "invalid_provider_response");
});

Deno.test("getSubscription missing data envelope is invalid_provider_response", async () => {
  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () =>
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
  });
  assertEquals(result.kind, "invalid_provider_response");
});

Deno.test("getSubscription oversized 2xx is invalid_provider_response once", async () => {
  let calls = 0;
  const first = new Uint8Array(PADDLE_MAX_RESPONSE_BYTES);
  first.fill(0x41);
  const extra = new Uint8Array([0x41]);
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(first);
      controller.enqueue(extra);
      controller.close();
    },
  });
  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () => {
      calls += 1;
      return new Response(stream, { status: 200 });
    },
  });
  assertEquals(calls, 1);
  assertEquals(result.kind, "invalid_provider_response");
});

Deno.test("getSubscription valid response no retry via reader", async () => {
  let calls = 0;
  const reader = createPaddleSandboxSubscriptionReader({
    env: () => "k",
    fetch: async () => {
      calls += 1;
      return new Response(JSON.stringify(subscriptionEnvelope()), {
        status: 200,
      });
    },
  });
  const result = await reader.getSubscription(SUB_ID);
  assertEquals(result.kind, "success");
  if (result.kind === "success") {
    assertEquals(result.data.id, SUB_ID);
    assertEquals(result.data.customer_id, CTM_ID);
  }
  assertEquals(calls, 1);
});

Deno.test("getSubscription returns next_billed_at from data", async () => {
  const result = await getPaddleSandboxSubscription(SUB_ID, {
    env: () => "k",
    fetch: async () =>
      new Response(
        JSON.stringify(
          subscriptionEnvelope({ next_billed_at: "2026-10-01T00:00:00.000Z" }),
        ),
        { status: 200 },
      ),
  });
  assertEquals(result.kind, "success");
  if (result.kind === "success") {
    assertEquals(result.data.next_billed_at, "2026-10-01T00:00:00.000Z");
  }
});

// ---------------------------------------------------------------------------
// PATCH next_billed_at preview + update — Step 18B
// ---------------------------------------------------------------------------

const NEXT = "2026-11-01T00:00:00.000Z";

const nextInput: PaddleUpdateNextBilledAtInput = {
  external_subscription_id: SUB_ID,
  next_billed_at: NEXT,
  proration_billing_mode: "do_not_bill",
};

interface SeenRequest {
  url: string;
  method: string;
  headers: Headers;
  bodyText: string;
}

function recordingFetch(
  seen: SeenRequest[],
  respond: () => Response,
): typeof fetch {
  return async (url, init) => {
    const opts = (init ?? {}) as RequestInit;
    seen.push({
      url: String(url),
      method: String(opts.method ?? "GET"),
      headers: new Headers(opts.headers),
      bodyText: String(opts.body ?? ""),
    });
    return respond();
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function previewEnvelope(overrides: Record<string, unknown> = {}) {
  return {
    data: {
      ...subscriptionEnvelope().data,
      next_billed_at: NEXT,
      immediate_transaction: null,
      next_transaction: {
        details: { totals: { total: "1000", grand_total: "1000" } },
      },
      update_summary: null,
      ...overrides,
    },
  };
}

function assertMinimalPatch(req: SeenRequest, expectedUrl: string) {
  assertEquals(req.url, expectedUrl);
  assertEquals(req.method, "PATCH");
  assertEquals(req.headers.get("Authorization"), "Bearer k");
  assertEquals(req.headers.get("Paddle-Version"), "1");
  assertEquals(req.headers.get("Content-Type"), "application/json");
  assertEquals(req.headers.get("Idempotency-Key"), null);
  assertEquals(
    req.bodyText,
    JSON.stringify({
      next_billed_at: NEXT,
      proration_billing_mode: "do_not_bill",
    }),
  );
  assertEquals(Object.keys(JSON.parse(req.bodyText)), [
    "next_billed_at",
    "proration_billing_mode",
  ]);
}

Deno.test("preview do_not_bill with no immediate charge is safe", async () => {
  const seen: SeenRequest[] = [];
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: recordingFetch(seen, () => jsonResponse(previewEnvelope())),
    },
  );
  assertEquals(result.kind, "safe");
  if (result.kind === "safe") {
    assertEquals(result.preview_next_billed_at, NEXT);
  }
  assertEquals(seen.length, 1);
  assertMinimalPatch(
    seen[0],
    `${PADDLE_SANDBOX_BASE_URL}/subscriptions/${SUB_ID}/preview`,
  );
});

Deno.test("preview with zero-total immediate_transaction is safe", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(previewEnvelope({
          immediate_transaction: {
            details: { totals: { total: "0", grand_total: "0" } },
          },
        })),
    },
  );
  assertEquals(result.kind, "safe");
});

Deno.test("preview with immediate_transaction charge is unsafe_immediate_charge", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(previewEnvelope({
          immediate_transaction: {
            details: { totals: { total: "1000", grand_total: "1190" } },
          },
        })),
    },
  );
  assertEquals(result.kind, "unsafe_immediate_charge");
  if (result.kind === "unsafe_immediate_charge") {
    assertEquals(result.immediate_grand_total, "1190");
  }
});

Deno.test("preview with update_summary charge is unsafe_immediate_charge", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(previewEnvelope({
          update_summary: {
            credit: { amount: "0", currency_code: "EUR" },
            charge: { amount: "500", currency_code: "EUR" },
            result: { action: "charge", amount: "500", currency_code: "EUR" },
          },
        })),
    },
  );
  assertEquals(result.kind, "unsafe_immediate_charge");
});

Deno.test("preview fails closed on unexpected shapes", async () => {
  const cases: Array<Record<string, unknown>> = [
    { immediate_transaction: { details: {} } },
    { immediate_transaction: { details: { totals: { grand_total: "abc" } } } },
    { immediate_transaction: { details: { totals: { grand_total: "-5" } } } },
    { next_billed_at: "2026-11-02T00:00:00.000Z" },
    { next_billed_at: null },
    { update_summary: { charge: { amount: null } } },
  ];
  for (const overrides of cases) {
    const result = await previewPaddleSandboxSubscriptionNextBilledAt(
      nextInput,
      {
        env: () => "k",
        fetch: async () => jsonResponse(previewEnvelope(overrides)),
      },
    );
    assertEquals(
      result.kind,
      "unsafe_unexpected",
      JSON.stringify(overrides),
    );
  }
});

Deno.test("preview maps definitive 4xx and 5xx", async () => {
  const rejected = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(
          { error: { code: "subscription_locked", detail: "locked" } },
          422,
        ),
    },
  );
  assertEquals(rejected.kind, "definitive_client_error");
  if (rejected.kind === "definitive_client_error") {
    assertEquals(rejected.http_status, 422);
    assertEquals(rejected.paddle_error_code, "subscription_locked");
  }

  const boom = await previewPaddleSandboxSubscriptionNextBilledAt(nextInput, {
    env: () => "k",
    fetch: async () => jsonResponse({ error: { detail: "boom" } }, 503),
  });
  assertEquals(boom.kind, "uncertain");
  if (boom.kind === "uncertain") assertEquals(boom.reason, "http_5xx");
});

Deno.test("preview HTTP 409 consent lock is definitive_client_error", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(
          {
            error: {
              code: "subscription_locked_consent_review_period",
              detail: "Subscription is locked during consent review",
            },
          },
          409,
        ),
    },
  );
  assertEquals(result.kind, "definitive_client_error");
  if (result.kind === "definitive_client_error") {
    assertEquals(result.http_status, 409);
    assertEquals(
      result.paddle_error_code,
      "subscription_locked_consent_review_period",
    );
    // Sanitized message may exist, but raw detail must not be required for code.
    assertEquals(
      typeof result.sanitized_message === "string" &&
        result.sanitized_message.length > 0,
      true,
    );
  }
});

Deno.test("preview HTTP 409 next_billed_at_too_soon is definitive_client_error", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(
          {
            error: {
              code: "subscription_next_billed_at_too_soon",
              detail: "next_billed_at is too soon",
            },
          },
          409,
        ),
    },
  );
  assertEquals(result.kind, "definitive_client_error");
  if (result.kind === "definitive_client_error") {
    assertEquals(result.http_status, 409);
    assertEquals(
      result.paddle_error_code,
      "subscription_next_billed_at_too_soon",
    );
  }
});

Deno.test("update PATCH HTTP 409 is definitive_client_error", async () => {
  const result = await updatePaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(
          {
            error: {
              code: "subscription_locked_consent_review_period",
              detail: "locked",
            },
          },
          409,
        ),
    },
  );
  assertEquals(result.kind, "definitive_client_error");
  if (result.kind === "definitive_client_error") {
    assertEquals(result.http_status, 409);
    assertEquals(
      result.paddle_error_code,
      "subscription_locked_consent_review_period",
    );
  }
});

Deno.test("createCheckout HTTP 409 remains uncertain (not subscription patch)", async () => {
  const adapter = createPaddleSandboxCheckoutAdapter({
    env: () => "k",
    fetch: async () =>
      new Response(
        JSON.stringify({
          error: {
            code: "subscription_locked_consent_review_period",
            detail: "locked",
          },
        }),
        { status: 409 },
      ),
  });
  const result = await adapter.createCheckout(input);
  assertEquals(result.kind, "uncertain");
});

Deno.test("preview HTTP 409 with unsafe error.code drops code", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(
          {
            error: {
              code: "bad code with spaces!!!",
              detail: "secret raw detail should be sanitized",
            },
          },
          409,
        ),
    },
  );
  assertEquals(result.kind, "definitive_client_error");
  if (result.kind === "definitive_client_error") {
    assertEquals(result.http_status, 409);
    assertEquals(result.paddle_error_code, null);
  }
});

Deno.test("preview timeout and network remain uncertain", async () => {
  const timeout = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () => {
        const err = new Error("Aborted");
        err.name = "AbortError";
        throw err;
      },
    },
  );
  assertEquals(timeout.kind, "uncertain");
  if (timeout.kind === "uncertain") assertEquals(timeout.reason, "timeout");

  const network = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () => {
        throw new Error("connect ECONNREFUSED");
      },
    },
  );
  assertEquals(network.kind, "uncertain");
  if (network.kind === "uncertain") assertEquals(network.reason, "network");
});

Deno.test("update PATCH sends exact minimal body and parses result", async () => {
  const seen: SeenRequest[] = [];
  const result = await updatePaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: recordingFetch(
        seen,
        () =>
          jsonResponse(subscriptionEnvelope({
            next_billed_at: NEXT,
            current_billing_period: {
              starts_at: "2026-09-01T00:00:00.000Z",
              ends_at: NEXT,
            },
          })),
      ),
    },
  );
  assertEquals(seen.length, 1);
  assertMinimalPatch(
    seen[0],
    `${PADDLE_SANDBOX_BASE_URL}/subscriptions/${SUB_ID}`,
  );
  assertEquals(result.kind, "success");
  if (result.kind === "success") {
    assertEquals(result.next_billed_at, NEXT);
    assertEquals(result.current_period_ends_at, NEXT);
    assertEquals(result.data.id, SUB_ID);
  }
});

Deno.test("update timeout and network are uncertain", async () => {
  const timeout = await updatePaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () => {
        const err = new Error("The signal has been aborted");
        err.name = "AbortError";
        throw err;
      },
    },
  );
  assertEquals(timeout.kind, "uncertain");
  if (timeout.kind === "uncertain") assertEquals(timeout.reason, "timeout");

  const network = await updatePaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () => {
        throw new TypeError("network down");
      },
    },
  );
  assertEquals(network.kind, "uncertain");
  if (network.kind === "uncertain") assertEquals(network.reason, "network");
});

Deno.test("preview timeout is uncertain", async () => {
  const result = await previewPaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () => {
        const err = new Error("Aborted");
        err.name = "AbortError";
        throw err;
      },
    },
  );
  assertEquals(result.kind, "uncertain");
  if (result.kind === "uncertain") assertEquals(result.reason, "timeout");
});

Deno.test("update 2xx without data or with mismatched id is uncertain", async () => {
  const missing = await updatePaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    { env: () => "k", fetch: async () => jsonResponse({ ok: true }) },
  );
  assertEquals(missing.kind, "uncertain");

  const mismatch = await updatePaddleSandboxSubscriptionNextBilledAt(
    nextInput,
    {
      env: () => "k",
      fetch: async () =>
        jsonResponse(
          subscriptionEnvelope({ id: "sub_01h4examplesubid0000000002" }),
        ),
    },
  );
  assertEquals(mismatch.kind, "uncertain");
});

Deno.test("update rejects invalid input locally without fetching", async () => {
  const invalid: PaddleUpdateNextBilledAtInput[] = [
    { ...nextInput, external_subscription_id: "sub_bad" },
    { ...nextInput, next_billed_at: "2026-11-01" },
    { ...nextInput, next_billed_at: "2026-11-01T00:00:00+02:00" },
    { ...nextInput, next_billed_at: "2026-02-30T00:00:00.000Z" },
    {
      ...nextInput,
      proration_billing_mode: "prorated_immediately" as "do_not_bill",
    },
  ];
  for (const input of invalid) {
    let calls = 0;
    const result = await updatePaddleSandboxSubscriptionNextBilledAt(input, {
      env: () => "k",
      fetch: async () => {
        calls += 1;
        return jsonResponse(subscriptionEnvelope());
      },
    });
    assertEquals(calls, 0, JSON.stringify(input));
    assertEquals(result.kind, "definitive_client_error");
    if (result.kind === "definitive_client_error") {
      assertEquals(result.http_status, 0);
    }
  }

  let calls = 0;
  const noKey = await updatePaddleSandboxSubscriptionNextBilledAt(nextInput, {
    env: () => undefined,
    fetch: async () => {
      calls += 1;
      return jsonResponse(subscriptionEnvelope());
    },
  });
  assertEquals(calls, 0);
  assertEquals(noKey.kind, "definitive_client_error");
});
