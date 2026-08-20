// deno-lint-ignore-file require-await
/**
 * Local Deno tests for billing-webhook-processor-paddle.
 * Synthetic secrets only — never real ATLAS_BILLING_PROCESSOR_INVOKE_SECRET.
 */

import { assertEquals, assertStringIncludes } from "@std/assert";
import { AtlasHttpError } from "../_shared/errors.ts";
import { createHandler } from "./handler.ts";
import { sanitizeApplyFailure } from "./sanitize.ts";
import {
  type ApplyRow,
  type ClaimNextRow,
  type HandlerDeps,
  PROCESSOR_INTERNAL_ERROR,
  PROCESSOR_INVOKE_HEADER,
  PROCESSOR_INVOKE_SECRET_ENV,
  type ProcessorRpcClient,
} from "./types.ts";

const SYNTH_SECRET = "test_atlas_billing_processor_invoke_secret_value";
const INBOX = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const CORR = "11111111-2222-4333-8444-555555555555";

type Call =
  | { name: "claimNext" }
  | { name: "apply"; id: string }
  | { name: "fail"; id: string; code: string };

function baseDeps(overrides: {
  env?: Record<string, string | undefined>;
  rpc?: Partial<ProcessorRpcClient>;
  calls?: Call[];
}): HandlerDeps {
  const calls = overrides.calls ?? [];
  const envMap: Record<string, string | undefined> = {
    [PROCESSOR_INVOKE_SECRET_ENV]: SYNTH_SECRET,
    SUPABASE_URL: "http://127.0.0.1:54321",
    SUPABASE_SERVICE_ROLE_KEY: "test_service_role_key_not_real",
    ...(overrides.env ?? {}),
  };

  const rpc: ProcessorRpcClient = {
    async claimNextPaddleSandboxWebhookEventServer() {
      calls.push({ name: "claimNext" });
      if (overrides.rpc?.claimNextPaddleSandboxWebhookEventServer) {
        return await overrides.rpc.claimNextPaddleSandboxWebhookEventServer();
      }
      return {
        outcome: "empty",
        inbox_event_id: null,
        processing_status: null,
        attempt_count: null,
      };
    },
    async applyPaddleSandboxWebhookEventServer(inboxEventId) {
      calls.push({ name: "apply", id: inboxEventId });
      if (overrides.rpc?.applyPaddleSandboxWebhookEventServer) {
        return await overrides.rpc.applyPaddleSandboxWebhookEventServer(
          inboxEventId,
        );
      }
      return {
        outcome: "applied",
        inbox_event_id: inboxEventId,
        processing_status: "processed",
        company_id: null,
        attempt_count: 1,
      };
    },
    async failPaddleSandboxWebhookEventProcessingServer(inboxEventId, code) {
      calls.push({ name: "fail", id: inboxEventId, code });
      if (overrides.rpc?.failPaddleSandboxWebhookEventProcessingServer) {
        return await overrides.rpc
          .failPaddleSandboxWebhookEventProcessingServer(
            inboxEventId,
            code,
          );
      }
      return {
        outcome: "failed",
        inbox_event_id: inboxEventId,
        processing_status: "failed",
        attempt_count: 1,
      };
    },
  };

  return {
    clock: () => new Date("2026-08-20T12:00:00.000Z"),
    uuid: () => CORR,
    env: (k) => envMap[k],
    rpc,
  };
}

function post(
  secret: string | null,
  body?: BodyInit | null,
  init?: RequestInit,
): Request {
  const headers = new Headers(init?.headers);
  if (secret !== null) headers.set(PROCESSOR_INVOKE_HEADER, secret);
  if (body !== undefined && body !== null && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }
  return new Request(
    "http://local/functions/v1/billing-webhook-processor-paddle",
    {
      method: init?.method ?? "POST",
      headers,
      body: body === undefined ? null : body,
    },
  );
}

async function readJson(res: Response): Promise<Record<string, unknown>> {
  return await res.json() as Record<string, unknown>;
}

function claimedRow(
  overrides: Partial<ClaimNextRow> = {},
): ClaimNextRow {
  return {
    outcome: "claimed",
    inbox_event_id: INBOX,
    processing_status: "processing",
    attempt_count: 1,
    ...overrides,
  };
}

function appliedRow(
  outcome: string,
  overrides: Partial<ApplyRow> = {},
): ApplyRow {
  const defaultStatus = outcome === "stale" || outcome === "ignored"
    ? "ignored"
    : "processed";
  return {
    outcome,
    inbox_event_id: INBOX,
    processing_status: defaultStatus,
    company_id: null,
    attempt_count: 1,
    ...overrides,
  };
}

function failedRow(
  overrides: Partial<{
    outcome: string;
    inbox_event_id: string | null;
    processing_status: string | null;
    attempt_count: number | null;
  }> = {},
) {
  return {
    outcome: "failed",
    inbox_event_id: INBOX,
    processing_status: "failed",
    attempt_count: 1,
    ...overrides,
  };
}

const OTHER_INBOX = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee";

// ---------------------------------------------------------------------------
// Auth / HTTP
// ---------------------------------------------------------------------------

Deno.test("POST + correct secret accepted (empty body)", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, null));
  assertEquals(res.status, 200);
  const body = await readJson(res);
  assertEquals(body.ok, true);
  assertEquals(body.outcome, "empty");
  assertEquals(body.correlation_id, CORR);
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("POST + correct secret accepts {}", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  assertEquals((await readJson(res)).outcome, "empty");
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("missing secret header → 401 and no RPC", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(null, "{}"));
  assertEquals(res.status, 401);
  const body = await readJson(res);
  assertEquals(body.error_code, "ATLAS_NOT_AUTHENTICATED");
  assertEquals(calls.length, 0);
});

Deno.test("wrong secret → 401 and no RPC", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post("wrong_secret_value_not_matching", "{}"));
  assertEquals(res.status, 401);
  assertEquals((await readJson(res)).error_code, "ATLAS_NOT_AUTHENTICATED");
  assertEquals(calls.length, 0);
});

Deno.test("missing server invoke-secret env → 503 fail closed", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    env: { [PROCESSOR_INVOKE_SECRET_ENV]: undefined },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 503);
  assertEquals((await readJson(res)).error_code, "ATLAS_INTERNAL_ERROR");
  assertEquals(calls.length, 0);
});

Deno.test("empty server invoke-secret env → 503 fail closed", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    env: { [PROCESSOR_INVOKE_SECRET_ENV]: "   " },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 503);
  assertEquals(calls.length, 0);
});

Deno.test("GET rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, null, { method: "GET" }));
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("Allow"), "POST");
  assertEquals(calls.length, 0);
});

Deno.test("PUT rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, "{}", { method: "PUT" }));
  assertEquals(res.status, 405);
  assertEquals(calls.length, 0);
});

Deno.test("PATCH rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, "{}", { method: "PATCH" }));
  assertEquals(res.status, 405);
  assertEquals(calls.length, 0);
});

Deno.test("DELETE rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, null, { method: "DELETE" }));
  assertEquals(res.status, 405);
  assertEquals(calls.length, 0);
});

Deno.test("malformed JSON rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, "{not-json"));
  assertEquals(res.status, 400);
  assertEquals((await readJson(res)).error_code, "ATLAS_INVALID_JSON");
  assertEquals(calls.length, 0);
});

Deno.test("arbitrary body field rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, JSON.stringify({ foo: 1 })));
  assertEquals(res.status, 400);
  assertEquals((await readJson(res)).error_code, "ATLAS_INVALID_REQUEST");
  assertEquals(calls.length, 0);
});

Deno.test("body containing inbox_event_id rejected", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(
    post(SYNTH_SECRET, JSON.stringify({ inbox_event_id: INBOX })),
  );
  assertEquals(res.status, 400);
  assertEquals(calls.length, 0);
});

// ---------------------------------------------------------------------------
// disabled / empty
// ---------------------------------------------------------------------------

Deno.test("claim_next disabled → no apply/fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => ({
        outcome: "disabled",
        inbox_event_id: null,
        processing_status: null,
        attempt_count: null,
      }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  const body = await readJson(res);
  assertEquals(body.outcome, "disabled");
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("claim_next empty → no apply/fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({ calls }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  assertEquals((await readJson(res)).outcome, "empty");
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

// ---------------------------------------------------------------------------
// claim / reclaim success
// ---------------------------------------------------------------------------

Deno.test("claimed → apply once, no fail on success", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async (id) => {
        assertEquals(id, INBOX);
        return appliedRow("applied");
      },
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  const body = await readJson(res);
  assertEquals(body.outcome, "processed");
  assertEquals(body.apply_outcome, "applied");
  assertEquals(body.inbox_event_id, INBOX);
  assertEquals(body.attempt_count, 1);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("reclaimed → apply once, no fail on success", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () =>
        claimedRow({ outcome: "reclaimed", attempt_count: 2 }),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("applied", { attempt_count: 2 }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  assertEquals((await readJson(res)).outcome, "processed");
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

// ---------------------------------------------------------------------------
// malformed / unexpected claim
// ---------------------------------------------------------------------------

Deno.test("claimed but null inbox UUID → fail closed, no apply", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () =>
        claimedRow({ inbox_event_id: null }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("claimed but malformed UUID → fail closed", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () =>
        claimedRow({ inbox_event_id: "not-a-uuid" }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("claimed but unexpected processing_status → fail closed", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () =>
        claimedRow({ processing_status: "received" }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("claimed but invalid attempt_count → fail closed", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () =>
        claimedRow({ attempt_count: 0 }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

Deno.test("unknown claim outcome → fail closed", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => ({
        outcome: "busy",
        inbox_event_id: INBOX,
        processing_status: "processing",
        attempt_count: 1,
      }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext"]);
});

// ---------------------------------------------------------------------------
// terminal apply outcomes
// ---------------------------------------------------------------------------

for (
  const terminal of [
    "applied",
    "already_processed",
    "ignored",
    "stale",
  ] as const
) {
  Deno.test(`terminal apply outcome ${terminal} → processed, no fail`, async () => {
    const calls: Call[] = [];
    const handler = createHandler(baseDeps({
      calls,
      rpc: {
        claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
        applyPaddleSandboxWebhookEventServer: async () => appliedRow(terminal),
      },
    }));
    const res = await handler(post(SYNTH_SECRET, "{}"));
    assertEquals(res.status, 200);
    const body = await readJson(res);
    assertEquals(body.outcome, "processed");
    assertEquals(body.apply_outcome, terminal);
    assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
  });
}

Deno.test("unexpected apply + processing → fail_finalized INTERNAL once", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("invalid_state", { processing_status: "processing" }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  const body = await readJson(res);
  assertEquals(body.outcome, "failed_finalized");
  assertEquals(body.error_code, PROCESSOR_INTERNAL_ERROR);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply", "fail"]);
  assertEquals((calls[2] as { code: string }).code, PROCESSOR_INTERNAL_ERROR);
});

Deno.test("unexpected apply + processed → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("invalid_state", { processing_status: "processed" }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("unexpected apply + UUID mismatch → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("invalid_state", {
          inbox_event_id: OTHER_INBOX,
          processing_status: "processing",
        }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("applied + wrong inbox UUID → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("applied", { inbox_event_id: OTHER_INBOX }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("applied + wrong processing_status → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("applied", { processing_status: "ignored" }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("terminal apply + invalid attempt_count → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("applied", { attempt_count: 0 }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("apply attempt_count != claim → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        appliedRow("applied", { attempt_count: 2 }),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

Deno.test("malformed apply object → 500, no fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () =>
        ({
          outcome: "applied",
          inbox_event_id: null,
          processing_status: "processed",
          company_id: null,
          attempt_count: 1,
        }) as ApplyRow,
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply"]);
});

// ---------------------------------------------------------------------------
// known / unknown apply errors
// ---------------------------------------------------------------------------

for (
  const code of [
    "ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD",
    "ATLAS_PROVIDER_EVENT_UNLINKED",
    "ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS",
  ] as const
) {
  Deno.test(`known apply error ${code} → fail once with same code`, async () => {
    const calls: Call[] = [];
    const handler = createHandler(baseDeps({
      calls,
      rpc: {
        claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
        applyPaddleSandboxWebhookEventServer: async () => {
          throw new AtlasHttpError(500, code, "Request failed");
        },
      },
    }));
    const res = await handler(post(SYNTH_SECRET, "{}"));
    assertEquals(res.status, 200);
    const body = await readJson(res);
    assertEquals(body.outcome, "failed_finalized");
    assertEquals(body.error_code, code);
    assertEquals(calls.map((c) => c.name), ["claimNext", "apply", "fail"]);
    assertEquals((calls[2] as { code: string }).code, code);
  });
}

Deno.test("plain internal error → ATLAS_PROCESSOR_INTERNAL_ERROR", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () => {
        throw new Error("relation does not exist");
      },
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  assertEquals((await readJson(res)).error_code, PROCESSOR_INTERNAL_ERROR);
  assertEquals((calls[2] as { code: string }).code, PROCESSOR_INTERNAL_ERROR);
});

Deno.test("unknown ATLAS_* code → INTERNAL", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () => {
        throw new AtlasHttpError(500, "ATLAS_TOTALLY_UNKNOWN_CODE", "x");
      },
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals((await readJson(res)).error_code, PROCESSOR_INTERNAL_ERROR);
});

Deno.test("multiple Atlas codes in one error → INTERNAL", async () => {
  assertEquals(
    sanitizeApplyFailure(
      "ATLAS_PROVIDER_EVENT_UNLINKED and ATLAS_PROVIDER_LINK_CONFLICT",
    ),
    PROCESSOR_INTERNAL_ERROR,
  );
});

Deno.test("malformed exception → INTERNAL", async () => {
  assertEquals(sanitizeApplyFailure(null), PROCESSOR_INTERNAL_ERROR);
  assertEquals(sanitizeApplyFailure(42), PROCESSOR_INTERNAL_ERROR);
});

// ---------------------------------------------------------------------------
// fail finalizer failure + bounds
// ---------------------------------------------------------------------------

Deno.test("fail finalizer failure → 500, no retries", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () => {
        throw new AtlasHttpError(
          500,
          "ATLAS_PROVIDER_EVENT_UNLINKED",
          "Request failed",
        );
      },
      failPaddleSandboxWebhookEventProcessingServer: async () => {
        throw new AtlasHttpError(500, "ATLAS_INTERNAL_ERROR", "Request failed");
      },
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 500);
  const body = await readJson(res);
  assertEquals(body.error_code, "ATLAS_INTERNAL_ERROR");
  assertStringIncludes(JSON.stringify(body), "ATLAS_INTERNAL_ERROR");
  // no raw SQL text
  assertEquals(JSON.stringify(body).includes("does not exist"), false);
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply", "fail"]);
});

Deno.test("one invocation bounds: at most one claim/apply/fail", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () => {
        throw new AtlasHttpError(
          500,
          "ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD",
          "Request failed",
        );
      },
    },
  }));
  await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(calls.filter((c) => c.name === "claimNext").length, 1);
  assertEquals(calls.filter((c) => c.name === "apply").length, 1);
  assertEquals(calls.filter((c) => c.name === "fail").length, 1);
});

Deno.test("response never echoes invoke secret", async () => {
  const handler = createHandler(baseDeps({}));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  const text = await res.text();
  assertEquals(text.includes(SYNTH_SECRET), false);
  assertEquals(text.includes(PROCESSOR_INVOKE_SECRET_ENV), false);
});

// ---------------------------------------------------------------------------
// fail-finalizer result validation
// ---------------------------------------------------------------------------

Deno.test("fail finalizer success shape → failed_finalized", async () => {
  const calls: Call[] = [];
  const handler = createHandler(baseDeps({
    calls,
    rpc: {
      claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
      applyPaddleSandboxWebhookEventServer: async () => {
        throw new AtlasHttpError(
          500,
          "ATLAS_PROVIDER_EVENT_UNLINKED",
          "Request failed",
        );
      },
      failPaddleSandboxWebhookEventProcessingServer: async () => failedRow(),
    },
  }));
  const res = await handler(post(SYNTH_SECRET, "{}"));
  assertEquals(res.status, 200);
  assertEquals((await readJson(res)).outcome, "failed_finalized");
  assertEquals(calls.map((c) => c.name), ["claimNext", "apply", "fail"]);
});

for (
  const bad of [
    {
      name: "invalid_state",
      row: () => failedRow({ outcome: "invalid_state" }),
    },
    { name: "processed", row: () => failedRow({ outcome: "processed" }) },
    { name: "ignored", row: () => failedRow({ outcome: "ignored" }) },
    { name: "unknown", row: () => failedRow({ outcome: "weird" }) },
    {
      name: "uuid_mismatch",
      row: () => failedRow({ inbox_event_id: OTHER_INBOX }),
    },
    {
      name: "status_not_failed",
      row: () => failedRow({ processing_status: "processing" }),
    },
    {
      name: "invalid_attempt",
      row: () => failedRow({ attempt_count: 0 }),
    },
    {
      name: "attempt_mismatch",
      row: () => failedRow({ attempt_count: 2 }),
    },
    {
      name: "malformed_uuid",
      row: () => failedRow({ inbox_event_id: "not-uuid" }),
    },
  ] as const
) {
  Deno.test(`fail finalizer ${bad.name} → 500, no retry`, async () => {
    const calls: Call[] = [];
    const handler = createHandler(baseDeps({
      calls,
      rpc: {
        claimNextPaddleSandboxWebhookEventServer: async () => claimedRow(),
        applyPaddleSandboxWebhookEventServer: async () => {
          throw new AtlasHttpError(
            500,
            "ATLAS_PROVIDER_EVENT_UNLINKED",
            "Request failed",
          );
        },
        failPaddleSandboxWebhookEventProcessingServer: async () => bad.row(),
      },
    }));
    const res = await handler(post(SYNTH_SECRET, "{}"));
    assertEquals(res.status, 500);
    assertEquals(calls.filter((c) => c.name === "claimNext").length, 1);
    assertEquals(calls.filter((c) => c.name === "apply").length, 1);
    assertEquals(calls.filter((c) => c.name === "fail").length, 1);
  });
}
