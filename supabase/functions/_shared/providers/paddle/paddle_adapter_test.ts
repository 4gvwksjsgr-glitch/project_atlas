// deno-lint-ignore-file require-await
/**
 * Paddle sandbox adapter tests — injected fake fetch only.
 */

import { assertEquals } from "@std/assert";
import {
  createPaddleSandboxCheckoutAdapter,
  isValidPaddleTransactionId,
  readResponseBodyWithLimit,
  validatePaddleCheckoutUrl,
} from "./paddle_adapter.ts";
import {
  PADDLE_MAX_RESPONSE_BYTES,
  PADDLE_SANDBOX_BASE_URL,
  type PaddleCreateCheckoutInput,
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
