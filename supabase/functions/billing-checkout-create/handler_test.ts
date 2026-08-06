// deno-lint-ignore-file require-await
/**
 * Handler orchestration tests with mocked deps (no real network).
 */

import { assertEquals } from "@std/assert";
import { handleCheckoutCreate, validateReservationRuntime } from "./handler.ts";
import { AtlasHttpError } from "../_shared/errors.ts";
import type {
  AttachBillingCheckoutProviderResultRow,
  HandlerDeps,
  ReserveBillingCheckoutSessionRow,
} from "./types.ts";
import type { PaddleCreateCheckoutResult } from "../_shared/providers/paddle/paddle_types.ts";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const ACTOR = "22222222-2222-4222-8222-222222222222";
const SESSION = "44444444-4444-4444-8444-444444444444";
const CORRELATION = "33333333-3333-4333-8333-333333333333";
const TXN = "txn_01abcdefghijklmnopqr";
const CHECKOUT_URL = `https://atlas.example/billing/checkout?_ptxn=${TXN}`;

function reservation(
  overrides: Partial<ReserveBillingCheckoutSessionRow> = {},
): ReserveBillingCheckoutSessionRow {
  return {
    session_id: SESSION,
    reuse: false,
    provider_environment: "test",
    billing_provider_price_id: "55555555-5555-4555-8555-555555555555",
    external_price_id: "pri_01testprice00000000000001",
    atlas_plan_code: "premium",
    offer_code: "premium_monthly",
    checkout_status: "created",
    provider_create_status: "not_started",
    return_token_plain: "rtok_plain",
    return_token_version: 1,
    expires_at: "2026-08-05T00:00:00.000Z",
    existing_checkout_url: null,
    existing_external_transaction_id: null,
    provider_code: "paddle",
    payment_page_origin: "https://atlas.example",
    checkout_path: "/billing/checkout",
    return_path: "/billing/return",
    checkout_page_url: "https://atlas.example/billing/checkout",
    ...overrides,
  };
}

interface Harness {
  deps: HandlerDeps;
  reserveCalls: number;
  attachCalls: Array<{
    expected_from: string;
    to_status: string;
  }>;
  paddleCalls: number;
  setReserve: (
    fn: () => Promise<ReserveBillingCheckoutSessionRow>,
  ) => void;
  setAttach: (
    fn: () => Promise<AttachBillingCheckoutProviderResultRow>,
  ) => void;
  setPaddle: (
    fn: () => Promise<PaddleCreateCheckoutResult>,
  ) => void;
}

function makeHarness(): Harness {
  let reserveFn = async () => reservation();
  let attachFn = async (): Promise<AttachBillingCheckoutProviderResultRow> => ({
    applied: true,
    session_id: SESSION,
    provider_create_status: "processing",
    checkout_status: "created",
  });
  let paddleFn = async (): Promise<PaddleCreateCheckoutResult> => ({
    kind: "success",
    external_transaction_id: TXN,
    checkout_url: CHECKOUT_URL,
  });

  const harness: Harness = {
    reserveCalls: 0,
    attachCalls: [],
    paddleCalls: 0,
    setReserve: (fn) => {
      reserveFn = fn;
    },
    setAttach: (fn) => {
      attachFn = fn;
    },
    setPaddle: (fn) => {
      paddleFn = fn;
    },
    deps: {
      fetch: async () => {
        throw new Error("fetch must not be used");
      },
      clock: () => new Date("2026-08-04T12:00:00.000Z"),
      uuid: () => CORRELATION,
      authLookup: async () => ({ id: ACTOR }),
      rpc: {
        reserveBillingCheckoutSessionServer: async () => {
          harness.reserveCalls += 1;
          return await reserveFn();
        },
        attachBillingCheckoutProviderResultServer: async (args) => {
          harness.attachCalls.push({
            expected_from: args.expected_from,
            to_status: args.to_status,
          });
          return await attachFn();
        },
      },
      paddle: {
        createCheckout: async () => {
          harness.paddleCalls += 1;
          return await paddleFn();
        },
      },
      corsAllowlist: ["https://app.atlas.example"],
      env: (key: string) =>
        key === "PADDLE_SANDBOX_API_KEY" ? "test-sandbox-key" : undefined,
    },
  };
  return harness;
}

function postReq(): Request {
  return new Request("http://local/billing-checkout-create", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer test-token",
      "Idempotency-Key": "idem-1",
      "Origin": "https://app.atlas.example",
    },
    body: JSON.stringify({ company_id: COMPANY }),
  });
}

Deno.test("state A created: no Paddle, reused true", async () => {
  const h = makeHarness();
  h.setReserve(async () =>
    reservation({
      provider_create_status: "created",
      reuse: true,
      existing_checkout_url: CHECKOUT_URL,
      existing_external_transaction_id: TXN,
    })
  );
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.reused, true);
  assertEquals(body.checkout_url, CHECKOUT_URL);
  assertEquals(h.paddleCalls, 0);
  assertEquals(h.attachCalls.length, 0);
});

Deno.test("state B processing: 409 in progress retryable, no Paddle", async () => {
  const h = makeHarness();
  h.setReserve(async () =>
    reservation({ provider_create_status: "processing" })
  );
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_CHECKOUT_IN_PROGRESS");
  assertEquals(body.retryable, true);
  assertEquals(h.paddleCalls, 0);
});

Deno.test("state C outcome_unknown: 409 not retryable, no Paddle", async () => {
  const h = makeHarness();
  h.setReserve(async () =>
    reservation({ provider_create_status: "outcome_unknown" })
  );
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_PROVIDER_OUTCOME_UNKNOWN");
  assertEquals(body.retryable, false);
  assertEquals(h.paddleCalls, 0);
});

Deno.test("state D not_started: attach then Paddle then created", async () => {
  const h = makeHarness();
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "created",
      checkout_status: "created",
    },
  ];
  h.setAttach(async () => attachResults.shift()!);

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.reused, false);
  assertEquals(body.checkout_session_id, SESSION);
  assertEquals(body.checkout_url, CHECKOUT_URL);
  assertEquals(h.paddleCalls, 1);
  assertEquals(h.attachCalls[0], {
    expected_from: "not_started",
    to_status: "processing",
  });
  assertEquals(h.attachCalls[1], {
    expected_from: "processing",
    to_status: "created",
  });
});

Deno.test("applied=false: one re-reserve, map to processing, never loop Paddle", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    return reservation({ provider_create_status: "processing" });
  });
  h.setAttach(async () => ({
    applied: false,
    session_id: SESSION,
    provider_create_status: null,
    checkout_status: null,
  }));

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_CHECKOUT_IN_PROGRESS");
  assertEquals(h.paddleCalls, 0);
  assertEquals(h.reserveCalls, 2);
  assertEquals(h.attachCalls.length, 1);
});

Deno.test("Paddle definitive 4xx attaches failed when applied=true", async () => {
  const h = makeHarness();
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "failed",
      checkout_status: "failed",
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 400,
    sanitized_message: "bad price",
  }));

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 502);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_PROVIDER_REQUEST_REJECTED");
  assertEquals(h.attachCalls[1]?.to_status, "failed");
  assertEquals(h.paddleCalls, 1);
});

Deno.test("Paddle 4xx attach applied=false: one reread, no second Paddle", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    return reservation({
      provider_create_status: "created",
      reuse: true,
      existing_checkout_url: CHECKOUT_URL,
      existing_external_transaction_id: TXN,
    });
  });
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 422,
    sanitized_message: "invalid",
  }));

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.reused, true);
  assertEquals(h.paddleCalls, 1);
  assertEquals(h.reserveCalls, 2);
});

Deno.test("Paddle 4xx attach applied=false maps processing", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    return reservation({ provider_create_status: "processing" });
  });
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 404,
    sanitized_message: "missing",
  }));
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error_code, "ATLAS_CHECKOUT_IN_PROGRESS");
  assertEquals(h.paddleCalls, 1);
});

Deno.test("Paddle 4xx attach applied=false maps outcome_unknown", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    return reservation({ provider_create_status: "outcome_unknown" });
  });
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 401,
    sanitized_message: "auth",
  }));
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  assertEquals(
    (await res.json()).error_code,
    "ATLAS_PROVIDER_OUTCOME_UNKNOWN",
  );
});

Deno.test("Paddle 4xx attach applied=false maps failed to definitive reject", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    return reservation({ provider_create_status: "failed" });
  });
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 403,
    sanitized_message: "forbidden",
  }));
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 502);
  assertEquals(
    (await res.json()).error_code,
    "ATLAS_PROVIDER_REQUEST_REJECTED",
  );
});

Deno.test("Paddle 4xx attach applied=false unexpected state → outcome_unknown", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    return reservation({ provider_create_status: "not_started" });
  });
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 400,
    sanitized_message: "bad",
  }));
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  assertEquals(
    (await res.json()).error_code,
    "ATLAS_PROVIDER_OUTCOME_UNKNOWN",
  );
  assertEquals(h.paddleCalls, 1);
});

Deno.test("Paddle 4xx attach applied=false contradictory created → outcome_unknown", async () => {
  const h = makeHarness();
  let reserves = 0;
  h.setReserve(async () => {
    reserves += 1;
    if (reserves === 1) {
      return reservation({ provider_create_status: "not_started" });
    }
    // Contradictory created: status created but missing/invalid txn+url.
    return reservation({
      provider_create_status: "created",
      reuse: true,
      existing_checkout_url: null,
      existing_external_transaction_id: null,
    });
  });
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "definitive_client_error",
    http_status: 422,
    sanitized_message: "rejected",
  }));

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_PROVIDER_OUTCOME_UNKNOWN");
  assertEquals(body.retryable, false);
  assertEquals(h.paddleCalls, 1);
  assertEquals(h.reserveCalls, 2);
  assertEquals(
    h.attachCalls.filter((c) => c.to_status === "failed").length,
    1,
  );
  assertEquals(h.attachCalls[0]?.to_status, "processing");
  assertEquals(JSON.stringify(body).includes("txn_"), false);
  assertEquals(JSON.stringify(body).includes(CHECKOUT_URL), false);
});

Deno.test("missing Paddle key: zero reserve/attach/paddle", async () => {
  const h = makeHarness();
  h.deps.env = () => undefined;
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 503);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_CHECKOUT_UNAVAILABLE");
  assertEquals(h.reserveCalls, 0);
  assertEquals(h.attachCalls.length, 0);
  assertEquals(h.paddleCalls, 0);
  assertEquals(JSON.stringify(body).toLowerCase().includes("sandbox"), false);
});

Deno.test("Paddle uncertain attaches outcome_unknown", async () => {
  const h = makeHarness();
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "outcome_unknown",
      checkout_status: "created",
    },
  ];
  h.setAttach(async () => attachResults.shift()!);
  h.setPaddle(async () => ({
    kind: "uncertain",
    reason: "timeout",
    sanitized_message: "Paddle request timed out",
  }));

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_PROVIDER_OUTCOME_UNKNOWN");
  assertEquals(body.retryable, false);
  assertEquals(h.attachCalls[1]?.to_status, "outcome_unknown");
});

Deno.test("Paddle success but attach not applied → outcome unknown", async () => {
  const h = makeHarness();
  const attachResults: AttachBillingCheckoutProviderResultRow[] = [
    {
      applied: true,
      session_id: SESSION,
      provider_create_status: "processing",
      checkout_status: "created",
    },
    {
      applied: false,
      session_id: SESSION,
      provider_create_status: null,
      checkout_status: null,
    },
  ];
  h.setAttach(async () => attachResults.shift()!);

  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_PROVIDER_OUTCOME_UNKNOWN");
});

Deno.test("validateReservationRuntime rejects non-paddle / non-test", () => {
  try {
    validateReservationRuntime(
      reservation({ provider_code: "stripe" }),
    );
    throw new Error("expected");
  } catch (e) {
    assertEquals((e as AtlasHttpError).errorCode, "ATLAS_CHECKOUT_UNAVAILABLE");
  }
  try {
    validateReservationRuntime(
      reservation({ provider_environment: "live" }),
    );
    throw new Error("expected");
  } catch (e) {
    assertEquals((e as AtlasHttpError).errorCode, "ATLAS_CHECKOUT_UNAVAILABLE");
  }
  try {
    validateReservationRuntime(
      reservation({ checkout_page_url: "http://insecure.example/x" }),
    );
    throw new Error("expected");
  } catch (e) {
    assertEquals((e as AtlasHttpError).errorCode, "ATLAS_CHECKOUT_UNAVAILABLE");
  }
});

Deno.test("always uses premium_monthly offer_code on reserve", async () => {
  const h = makeHarness();
  let seenOffer = "";
  h.deps.rpc.reserveBillingCheckoutSessionServer = async (args) => {
    seenOffer = args.offer_code;
    h.reserveCalls += 1;
    return reservation({
      provider_create_status: "created",
      existing_checkout_url: CHECKOUT_URL,
      existing_external_transaction_id: TXN,
    });
  };
  await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(seenOffer, "premium_monthly");
});

Deno.test("unauthenticated returns 401", async () => {
  const h = makeHarness();
  h.deps.authLookup = async () => null;
  const res = await handleCheckoutCreate(postReq(), h.deps);
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_NOT_AUTHENTICATED");
  assertEquals(h.reserveCalls, 0);
});
