/**
 * Local Deno tests for Paddle webhook signature + inbox handler.
 * Synthetic secrets only — never real PADDLE_SANDBOX_WEBHOOK_SECRET.
 */

import { assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import { AtlasHttpError } from "../_shared/errors.ts";
import { sha256HexLower } from "./crypto_hash.ts";
import { createHandler } from "./handler.ts";
import { isRfc3339DateTime, parseVerifiedWebhookPayload } from "./payload.ts";
import {
  isTimestampWithinTolerance,
  parsePaddleSignatureHeader,
  verifyPaddleSignature,
} from "./signature.ts";
import type {
  BillingWebhookRpcClient,
  HandlerDeps,
  IngestPaddleSandboxWebhookEventArgs,
  IngestPaddleSandboxWebhookEventRow,
} from "./types.ts";
import {
  PADDLE_EVENT_ID_RE,
  WEBHOOK_MAX_BODY_BYTES,
  WEBHOOK_SECRET_ENV,
  WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
} from "./types.ts";

const SYNTH_SECRET = "test_paddle_sandbox_webhook_secret_value";
const EVT = "evt_" + "a".repeat(26);
const SIM_EVT = "ntfsimevt_" + "a".repeat(26);
const SUB = "sub_" + "b".repeat(26);
const NOW_MS = Date.parse("2026-08-10T12:00:00.000Z");

function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

async function hmacHex(
  secret: string,
  ts: number,
  rawBody: Uint8Array,
): Promise<string> {
  const enc = new TextEncoder();
  const prefix = enc.encode(`${ts}:`);
  const signed = new Uint8Array(prefix.byteLength + rawBody.byteLength);
  signed.set(prefix, 0);
  signed.set(rawBody, prefix.byteLength);
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, signed));
  let out = "";
  for (let i = 0; i < mac.length; i++) {
    out += mac[i]!.toString(16).padStart(2, "0");
  }
  return out;
}

function samplePayload(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    event_id: EVT,
    event_type: "subscription.created",
    occurred_at: "2026-08-10T12:00:00.000Z",
    data: { id: SUB },
    ...overrides,
  });
}

Deno.test("parsePaddleSignatureHeader requires ts and h1", () => {
  assertEquals(parsePaddleSignatureHeader(null).ok, false);
  assertEquals(parsePaddleSignatureHeader("").ok, false);
  assertEquals(parsePaddleSignatureHeader("ts=1").ok, false);
  assertEquals(parsePaddleSignatureHeader("h1=" + "a".repeat(64)).ok, false);
  assertEquals(
    parsePaddleSignatureHeader("ts=abc;h1=" + "a".repeat(64)).ok,
    false,
  );
  const ok = parsePaddleSignatureHeader(
    `ts=100;h1=${"a".repeat(64)};h1=${"b".repeat(64)}`,
  );
  assertEquals(ok.ok, true);
  if (ok.ok) {
    assertEquals(ok.value.ts, 100);
    assertEquals(ok.value.h1.length, 2);
  }
});

Deno.test("timestamp tolerance boundary is 5 seconds", () => {
  const nowSec = Math.floor(NOW_MS / 1000);
  assertEquals(
    isTimestampWithinTolerance(
      nowSec,
      NOW_MS,
      WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
    ),
    true,
  );
  assertEquals(
    isTimestampWithinTolerance(
      nowSec - 5,
      NOW_MS,
      WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
    ),
    true,
  );
  assertEquals(
    isTimestampWithinTolerance(
      nowSec + 5,
      NOW_MS,
      WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
    ),
    true,
  );
  assertEquals(
    isTimestampWithinTolerance(
      nowSec - 6,
      NOW_MS,
      WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
    ),
    false,
  );
  assertEquals(
    isTimestampWithinTolerance(
      nowSec + 6,
      NOW_MS,
      WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
    ),
    false,
  );
});

Deno.test("verifyPaddleSignature accepts valid signature", async () => {
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000);
  const h1 = await hmacHex(SYNTH_SECRET, ts, body);
  const r = await verifyPaddleSignature({
    header: `ts=${ts};h1=${h1}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(r.ok, true);
});

Deno.test("verifyPaddleSignature rejects invalid signature", async () => {
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000);
  const r = await verifyPaddleSignature({
    header: `ts=${ts};h1=${"0".repeat(64)}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(r.ok, false);
});

Deno.test("verifyPaddleSignature rejects stale and future timestamps", async () => {
  const body = utf8(samplePayload());
  const nowSec = Math.floor(NOW_MS / 1000);

  const staleTs = nowSec - 6;
  const staleH1 = await hmacHex(SYNTH_SECRET, staleTs, body);
  const stale = await verifyPaddleSignature({
    header: `ts=${staleTs};h1=${staleH1}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(stale.ok, false);

  const futureTs = nowSec + 6;
  const futureH1 = await hmacHex(SYNTH_SECRET, futureTs, body);
  const future = await verifyPaddleSignature({
    header: `ts=${futureTs};h1=${futureH1}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(future.ok, false);
});

Deno.test("verifyPaddleSignature accepts boundary timestamp", async () => {
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000) - 5;
  const h1 = await hmacHex(SYNTH_SECRET, ts, body);
  const r = await verifyPaddleSignature({
    header: `ts=${ts};h1=${h1}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(r.ok, true);
});

Deno.test("verifyPaddleSignature accepts multiple h1 with one valid", async () => {
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000);
  const good = await hmacHex(SYNTH_SECRET, ts, body);
  const r = await verifyPaddleSignature({
    header: `ts=${ts};h1=${"f".repeat(64)};h1=${good}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(r.ok, true);
});

Deno.test("verifyPaddleSignature rejects all-invalid multiple h1", async () => {
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000);
  const r = await verifyPaddleSignature({
    header: `ts=${ts};h1=${"1".repeat(64)};h1=${"2".repeat(64)}`,
    rawBody: body,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(r.ok, false);
});

Deno.test("verifyPaddleSignature is raw-body sensitive", async () => {
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000);
  const h1 = await hmacHex(SYNTH_SECRET, ts, body);
  const mutated = utf8(samplePayload() + " ");
  const r = await verifyPaddleSignature({
    header: `ts=${ts};h1=${h1}`,
    rawBody: mutated,
    secret: SYNTH_SECRET,
    nowMs: NOW_MS,
  });
  assertEquals(r.ok, false);
});

Deno.test("parseVerifiedWebhookPayload classifies supported and ignored", () => {
  const supported = parseVerifiedWebhookPayload(samplePayload());
  assertEquals(supported.ok, true);
  if (supported.ok) {
    assertEquals(supported.value.classification, "supported");
    assertEquals(supported.value.external_subscription_id, SUB);
  }

  const activated = parseVerifiedWebhookPayload(
    samplePayload({ event_type: "subscription.activated" }),
  );
  assertEquals(activated.ok, true);
  if (activated.ok) {
    assertEquals(activated.value.classification, "supported");
    assertEquals(activated.value.event_type, "subscription.activated");
    assertEquals(activated.value.external_subscription_id, SUB);
  }

  const ignored = parseVerifiedWebhookPayload(
    samplePayload({ event_type: "transaction.payment_failed", data: {} }),
  );
  assertEquals(ignored.ok, true);
  if (ignored.ok) {
    assertEquals(ignored.value.classification, "ignored");
  }

  assertEquals(parseVerifiedWebhookPayload("{").ok, false);
  assertEquals(parseVerifiedWebhookPayload("[]").ok, false);
});

Deno.test("PADDLE_EVENT_ID_RE accepts evt_ and ntfsimevt_ only", () => {
  assertEquals(PADDLE_EVENT_ID_RE.test(EVT), true);
  assertEquals(PADDLE_EVENT_ID_RE.test(SIM_EVT), true);
  assertEquals(PADDLE_EVENT_ID_RE.test("xyz_" + "a".repeat(26)), false);
  assertEquals(PADDLE_EVENT_ID_RE.test("ntfsimevt_" + "a".repeat(25)), false);
  assertEquals(PADDLE_EVENT_ID_RE.test("ntfsimevt_" + "a".repeat(27)), false);
  assertEquals(
    PADDLE_EVENT_ID_RE.test("NTFSIMEVT_" + "a".repeat(26)),
    false,
  );
  assertEquals(PADDLE_EVENT_ID_RE.test("ntfsimntf_" + "a".repeat(26)), false);
});

Deno.test("parseVerifiedWebhookPayload accepts simulator event id", () => {
  const parsed = parseVerifiedWebhookPayload(
    samplePayload({
      event_id: SIM_EVT,
      event_type: "transaction.completed",
      data: {},
    }),
  );
  assertEquals(parsed.ok, true);
  if (parsed.ok) {
    assertEquals(parsed.value.event_id, SIM_EVT);
    assertEquals(parsed.value.classification, "supported");
  }
});

Deno.test("parseVerifiedWebhookPayload rejects bad event id shapes", () => {
  assertEquals(
    parseVerifiedWebhookPayload(
      samplePayload({ event_id: "xyz_" + "a".repeat(26) }),
    ).ok,
    false,
  );
  assertEquals(
    parseVerifiedWebhookPayload(
      samplePayload({ event_id: "ntfsimevt_" + "a".repeat(25) }),
    ).ok,
    false,
  );
  assertEquals(
    parseVerifiedWebhookPayload(
      samplePayload({ event_id: "NTFSIMEVT_" + "a".repeat(26) }),
    ).ok,
    false,
  );
  assertEquals(
    parseVerifiedWebhookPayload(
      samplePayload({ event_id: "ntfsimntf_" + "a".repeat(26) }),
    ).ok,
    false,
  );
});

type RpcCall = {
  name: string;
  args: IngestPaddleSandboxWebhookEventArgs;
};

function mockRpc(
  impl: (
    args: IngestPaddleSandboxWebhookEventArgs,
  ) =>
    | IngestPaddleSandboxWebhookEventRow
    | Promise<IngestPaddleSandboxWebhookEventRow>,
): { client: BillingWebhookRpcClient; calls: RpcCall[] } {
  const calls: RpcCall[] = [];
  return {
    calls,
    client: {
      async ingestPaddleSandboxWebhookEventServer(args) {
        calls.push({ name: "ingestPaddleSandboxWebhookEventServer", args });
        return await impl(args);
      },
    },
  };
}

function makeDeps(
  rpc: BillingWebhookRpcClient,
  envOverrides: Record<string, string | undefined> = {},
): HandlerDeps {
  return {
    clock: () => new Date(NOW_MS),
    uuid: () => "11111111-1111-4111-8111-111111111111",
    env: (key) => {
      if (key in envOverrides) return envOverrides[key];
      if (key === WEBHOOK_SECRET_ENV) return SYNTH_SECRET;
      return undefined;
    },
    rpc,
  };
}

async function signedRequest(
  bodyText: string,
  init: {
    method?: string;
    contentType?: string | null;
    extraHeaders?: Record<string, string>;
    contentLength?: string;
  } = {},
): Promise<Request> {
  const body = utf8(bodyText);
  const ts = Math.floor(NOW_MS / 1000);
  const h1 = await hmacHex(SYNTH_SECRET, ts, body);
  const headers = new Headers();
  if (init.contentType !== null) {
    headers.set("Content-Type", init.contentType ?? "application/json");
  }
  headers.set("Paddle-Signature", `ts=${ts};h1=${h1}`);
  if (init.contentLength !== undefined) {
    headers.set("Content-Length", init.contentLength);
  }
  if (init.extraHeaders) {
    for (const [k, v] of Object.entries(init.extraHeaders)) {
      headers.set(k, v);
    }
  }
  return new Request("http://local/billing-webhook-paddle", {
    method: init.method ?? "POST",
    headers,
    body,
  });
}

Deno.test(
  "handler accepts signed simulator transaction.completed with ntfsimevt_",
  async () => {
    const { client, calls } = mockRpc(() => ({
      outcome: "inserted",
      inbox_event_id: "22222222-2222-4222-8222-222222222222",
    }));
    const handler = createHandler(makeDeps(client));
    const body = samplePayload({
      event_id: SIM_EVT,
      event_type: "transaction.completed",
      data: {},
    });
    const res = await handler(await signedRequest(body));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { ok: true });
    assertEquals(calls.length, 1);
    assertEquals(calls[0]!.name, "ingestPaddleSandboxWebhookEventServer");
    assertEquals(calls[0]!.args.external_event_id, SIM_EVT);
    assertEquals(calls[0]!.args.classification, "supported");
    assertEquals(calls[0]!.args.event_type, "transaction.completed");
  },
);

Deno.test("handler valid supported event returns 200 and calls inbox RPC", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true });
  assertEquals(calls.length, 1);
  assertEquals(calls[0]!.name, "ingestPaddleSandboxWebhookEventServer");
  assertEquals(calls[0]!.args.classification, "supported");
  assertEquals(calls[0]!.args.external_event_id, EVT);
  assertEquals(calls[0]!.args.payload_hash.length, 64);
  assertEquals("now" in calls[0]!.args, false);
  assertEquals(
    Object.prototype.hasOwnProperty.call(calls[0]!.args, "now"),
    false,
  );
});

Deno.test("handler unsupported verified event is ignored classification", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const body = samplePayload({
    event_id: "evt_" + "c".repeat(26),
    event_type: "transaction.payment_failed",
    data: {},
  });
  const res = await handler(await signedRequest(body));
  assertEquals(res.status, 200);
  assertEquals(calls[0]!.args.classification, "ignored");
});

Deno.test("handler duplicate same hash returns 200", async () => {
  const { client } = mockRpc(() => ({
    outcome: "duplicate",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.status, 200);
});

Deno.test("handler event-id/hash conflict returns sanitized 500", async () => {
  const { client } = mockRpc(() => {
    throw new AtlasHttpError(
      500,
      "ATLAS_PROVIDER_EVENT_PAYLOAD_CONFLICT",
      "Provider event conflict",
    );
  });
  const handler = createHandler(makeDeps(client));
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_PROVIDER_EVENT_PAYLOAD_CONFLICT");
  assertEquals("secret" in body, false);
});

Deno.test("handler DB failure returns sanitized 500", async () => {
  const { client } = mockRpc(() => {
    throw new AtlasHttpError(500, "ATLAS_INTERNAL_ERROR", "Request failed");
  });
  const handler = createHandler(makeDeps(client));
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error_code, "ATLAS_INTERNAL_ERROR");
});

Deno.test("handler missing secret returns 503 without RPC", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(
    makeDeps(client, { [WEBHOOK_SECRET_ENV]: undefined }),
  );
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.status, 503);
  assertEquals(calls.length, 0);
});

Deno.test("handler invalid signature returns 401 without RPC", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const body = utf8(samplePayload());
  const req = new Request("http://local/billing-webhook-paddle", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Paddle-Signature": `ts=${Math.floor(NOW_MS / 1000)};h1=${
        "0".repeat(64)
      }`,
    },
    body,
  });
  const res = await handler(req);
  assertEquals(res.status, 401);
  assertEquals(calls.length, 0);
});

Deno.test("handler malformed JSON after valid signature returns 400", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(await signedRequest("{not-json"));
  assertEquals(res.status, 400);
  assertEquals(calls.length, 0);
});

Deno.test("handler non-POST returns 405 with Allow POST", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(
    new Request("http://local/billing-webhook-paddle", { method: "GET" }),
  );
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("Allow"), "POST");
  assertEquals(calls.length, 0);
});

Deno.test("handler unsupported Content-Type returns 415", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(
    await signedRequest(samplePayload(), { contentType: "text/plain" }),
  );
  assertEquals(res.status, 415);
  assertEquals(calls.length, 0);
});

Deno.test("handler allows application/json with charset", async () => {
  const { client } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(
    await signedRequest(samplePayload(), {
      contentType: "application/json; charset=utf-8",
    }),
  );
  assertEquals(res.status, 200);
});

Deno.test("handler oversized Content-Length returns 413", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const body = utf8(samplePayload());
  const ts = Math.floor(NOW_MS / 1000);
  const h1 = await hmacHex(SYNTH_SECRET, ts, body);
  const req = new Request("http://local/billing-webhook-paddle", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": String(WEBHOOK_MAX_BODY_BYTES + 1),
      "Paddle-Signature": `ts=${ts};h1=${h1}`,
    },
    body,
  });
  const res = await handler(req);
  assertEquals(res.status, 413);
  assertEquals(calls.length, 0);
});

Deno.test("handler oversized streamed body returns 413", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const big = new Uint8Array(WEBHOOK_MAX_BODY_BYTES + 1);
  big.fill(0x61);
  const ts = Math.floor(NOW_MS / 1000);
  const h1 = await hmacHex(SYNTH_SECRET, ts, big);
  const req = new Request("http://local/billing-webhook-paddle", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Paddle-Signature": `ts=${ts};h1=${h1}`,
    },
    body: big,
  });
  const res = await handler(req);
  assertEquals(res.status, 413);
  assertEquals(calls.length, 0);
});

Deno.test("handler responses have no CORS headers and no secret leakage", async () => {
  const { client } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), null);
  assertEquals(res.headers.get("Access-Control-Allow-Credentials"), null);
  const text = await res.text();
  assertEquals(text.includes(SYNTH_SECRET), false);
  assertEquals(text.includes("Paddle-Signature"), false);
});

Deno.test("handler never invokes entitlement or billing mutation RPCs", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  await handler(await signedRequest(samplePayload()));
  assertEquals(calls.length, 1);
  assertEquals(calls[0]!.name, "ingestPaddleSandboxWebhookEventServer");
});

Deno.test("sha256HexLower is 64 lowercase hex", async () => {
  const hex = await sha256HexLower(utf8("abc"));
  assertEquals(hex.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(hex), true);
});

Deno.test("readBodyWithLimit rejects via AtlasHttpError for oversized", async () => {
  const { readBodyWithLimit } = await import("../_shared/http.ts");
  const req = new Request("http://local", {
    method: "POST",
    headers: { "Content-Length": String(WEBHOOK_MAX_BODY_BYTES + 1) },
    body: "x",
  });
  await assertRejects(
    () => readBodyWithLimit(req, WEBHOOK_MAX_BODY_BYTES),
    AtlasHttpError,
  );
});

Deno.test("error body does not include signature header values", async () => {
  const { client } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(makeDeps(client));
  const body = utf8(samplePayload());
  const badSig = `ts=${Math.floor(NOW_MS / 1000)};h1=${"ab".repeat(32)}`;
  const req = new Request("http://local/billing-webhook-paddle", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Paddle-Signature": badSig,
    },
    body,
  });
  const res = await handler(req);
  const text = await res.text();
  assertEquals(text.includes(badSig), false);
  assertEquals(text.includes(SYNTH_SECRET), false);
  assertStringIncludes(text, "ATLAS_WEBHOOK_SIGNATURE_INVALID");
});

Deno.test("missing secret with invalid Content-Type returns 415 before 503", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(
    makeDeps(client, { [WEBHOOK_SECRET_ENV]: undefined }),
  );
  const res = await handler(
    await signedRequest(samplePayload(), { contentType: "text/plain" }),
  );
  assertEquals(res.status, 415);
  assertEquals(calls.length, 0);
});

Deno.test("missing secret with oversized Content-Length returns 413 before 503", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(
    makeDeps(client, { [WEBHOOK_SECRET_ENV]: undefined }),
  );
  const body = utf8(samplePayload());
  const req = new Request("http://local/billing-webhook-paddle", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": String(WEBHOOK_MAX_BODY_BYTES + 1),
      "Paddle-Signature": `ts=${Math.floor(NOW_MS / 1000)};h1=${
        "0".repeat(64)
      }`,
    },
    body,
  });
  const res = await handler(req);
  assertEquals(res.status, 413);
  assertEquals(calls.length, 0);
});

Deno.test("valid request shape with missing secret returns 503", async () => {
  const { client, calls } = mockRpc(() => ({
    outcome: "inserted",
    inbox_event_id: "22222222-2222-4222-8222-222222222222",
  }));
  const handler = createHandler(
    makeDeps(client, { [WEBHOOK_SECRET_ENV]: undefined }),
  );
  const res = await handler(await signedRequest(samplePayload()));
  assertEquals(res.status, 503);
  assertEquals(calls.length, 0);
});

Deno.test("isRfc3339DateTime accepts valid RFC3339 and rejects invalid", () => {
  assertEquals(isRfc3339DateTime("2026-08-10T12:00:00Z"), true);
  assertEquals(isRfc3339DateTime("2026-08-10T12:00:00.123Z"), true);
  assertEquals(isRfc3339DateTime("2026-08-10T14:00:00+02:00"), true);
  assertEquals(isRfc3339DateTime("2026-02-28T23:59:59-05:30"), true);

  assertEquals(isRfc3339DateTime("2026-08-10"), false); // date-only
  assertEquals(isRfc3339DateTime("2026-08-10T12:00:00"), false); // missing tz
  assertEquals(isRfc3339DateTime("2026-08-10T12:00:00+25:00"), false); // bad tz
  assertEquals(isRfc3339DateTime("2026-02-30T12:00:00Z"), false); // impossible
  assertEquals(isRfc3339DateTime("2026-08-10T24:00:00Z"), false); // impossible hour
  assertEquals(isRfc3339DateTime("2026-08-10T12:00:00Ztrailing"), false);
  assertEquals(isRfc3339DateTime(" 2026-08-10T12:00:00Z"), false);
  assertEquals(isRfc3339DateTime("2026-08-10 12:00:00Z"), false);

  assertEquals(
    parseVerifiedWebhookPayload(
      samplePayload({ occurred_at: "2026-08-10" }),
    ).ok,
    false,
  );
  assertEquals(
    parseVerifiedWebhookPayload(
      samplePayload({ occurred_at: "2026-08-10T12:00:00Z" }),
    ).ok,
    true,
  );
});
