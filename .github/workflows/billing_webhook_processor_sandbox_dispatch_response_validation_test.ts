/**
 * Offline regression for billing-webhook-processor-sandbox-dispatch.yml
 * response-validation contract (14C-2H C8C).
 *
 * Mirrors schedule workflow HTTP 200 outcome allowlist / exit behavior.
 * Does not call the Edge Function or GitHub Actions.
 *
 * Run:
 *   .tools/deno/deno.exe test --allow-read .github/workflows/billing_webhook_processor_sandbox_dispatch_response_validation_test.ts
 */

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

const ROOT = new URL("../../", import.meta.url);
const DISPATCH = new URL(
  "./billing-webhook-processor-sandbox-dispatch.yml",
  import.meta.url,
);
const SCHEDULE = new URL(
  "./billing-webhook-processor-sandbox-schedule.yml",
  import.meta.url,
);

const UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const INBOX_UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;
const APPLY_OUTCOMES = new Set([
  "applied",
  "already_processed",
  "ignored",
  "stale",
]);
const ALLOWED_OUTCOMES = new Set([
  "disabled",
  "empty",
  "processed",
  "failed_finalized",
]);

/** Exit codes matching workflow case branches. */
type ValidateResult = { exitCode: number; reason: string };

/**
 * Offline port of the schedule/dispatch response validator after curl returns.
 * Body is never logged.
 */
export function validateProcessorHttpResponse(
  httpStatus: string,
  bodyText: string,
): ValidateResult {
  if (httpStatus !== "200") {
    return { exitCode: 1, reason: "non_200" };
  }

  let body: unknown;
  try {
    body = JSON.parse(bodyText);
  } catch {
    return { exitCode: 1, reason: "malformed_json" };
  }

  if (
    body === null ||
    typeof body !== "object" ||
    Array.isArray(body)
  ) {
    return { exitCode: 1, reason: "not_object" };
  }

  const o = body as Record<string, unknown>;
  if (o.ok !== true) {
    return { exitCode: 1, reason: "ok_not_true" };
  }
  if (typeof o.outcome !== "string" || !ALLOWED_OUTCOMES.has(o.outcome)) {
    return { exitCode: 1, reason: "unknown_or_invalid_outcome" };
  }
  if (typeof o.correlation_id !== "string" || !UUID_RE.test(o.correlation_id)) {
    return { exitCode: 1, reason: "bad_correlation_id" };
  }

  const outcome = o.outcome;
  if (outcome === "disabled" || outcome === "empty") {
    return { exitCode: 0, reason: outcome };
  }

  if (outcome === "processed") {
    if (
      typeof o.inbox_event_id !== "string" ||
      !INBOX_UUID_RE.test(o.inbox_event_id) ||
      typeof o.attempt_count !== "number" ||
      !Number.isInteger(o.attempt_count) ||
      o.attempt_count < 1 ||
      typeof o.apply_outcome !== "string" ||
      !APPLY_OUTCOMES.has(o.apply_outcome)
    ) {
      return { exitCode: 1, reason: "processed_shape_invalid" };
    }
    return { exitCode: 0, reason: "processed" };
  }

  // failed_finalized — controlled Actions failure
  if (
    typeof o.inbox_event_id !== "string" ||
    !INBOX_UUID_RE.test(o.inbox_event_id) ||
    typeof o.attempt_count !== "number" ||
    !Number.isInteger(o.attempt_count) ||
    o.attempt_count < 1 ||
    typeof o.error_code !== "string" ||
    o.error_code.length === 0 ||
    !/^ATLAS_[A-Z0-9_]+$/.test(o.error_code)
  ) {
    return { exitCode: 1, reason: "failed_finalized_shape_invalid" };
  }
  return { exitCode: 1, reason: "failed_finalized" };
}

function extractPostCurlValidation(yml: string): string {
  const marker = 'if [ "$HTTP_STATUS" != "200" ]; then';
  const idx = yml.indexOf(marker);
  if (idx < 0) throw new Error("HTTP_STATUS gate not found");
  // From after the non-200 block through end of run script (YAML ends at file for these workflows)
  const fromStatus = yml.slice(idx);
  const esacIdx = fromStatus.lastIndexOf("esac");
  if (esacIdx < 0) throw new Error("case/esac not found");
  return fromStatus.slice(0, esacIdx + "esac".length).replace(/\r\n/g, "\n");
}

Deno.test("dispatch validation fragment matches schedule (no contract drift)", () => {
  const dispatch = Deno.readTextFileSync(DISPATCH);
  const schedule = Deno.readTextFileSync(SCHEDULE);
  assertEquals(
    extractPostCurlValidation(dispatch),
    extractPostCurlValidation(schedule),
  );
});

Deno.test("dispatch keeps one POST / zero retries", () => {
  const dispatch = Deno.readTextFileSync(DISPATCH);
  assertStringIncludes(dispatch, "HTTP_POST_COUNT=1");
  assertStringIncludes(dispatch, "HTTP_RETRY_COUNT=0");
  const postCount = (dispatch.match(/-X POST/g) ?? []).length;
  assertEquals(postCount, 1);
  assertEquals(dispatch.includes("disabled expected"), false);
  // Reject any curl --retry* option (e.g. --retry, --retry-all-errors).
  assertEquals(/--retry/.test(dispatch), false);
});

const CORR = "a79d40c1-3a35-458a-a11d-cfee9c0d674a";
const INBOX = "a79d40c1-3a35-458a-a11d-cfee9c0d674a";

Deno.test("A valid disabled => success", () => {
  const r = validateProcessorHttpResponse(
    "200",
    JSON.stringify({ ok: true, outcome: "disabled", correlation_id: CORR }),
  );
  assertEquals(r.exitCode, 0);
});

Deno.test("B valid empty => success", () => {
  const r = validateProcessorHttpResponse(
    "200",
    JSON.stringify({ ok: true, outcome: "empty", correlation_id: CORR }),
  );
  assertEquals(r.exitCode, 0);
});

Deno.test("C valid processed => success", () => {
  const r = validateProcessorHttpResponse(
    "200",
    JSON.stringify({
      ok: true,
      outcome: "processed",
      correlation_id: CORR,
      inbox_event_id: INBOX,
      attempt_count: 1,
      apply_outcome: "applied",
    }),
  );
  assertEquals(r.exitCode, 0);
});

Deno.test("D valid failed_finalized => controlled failure", () => {
  const r = validateProcessorHttpResponse(
    "200",
    JSON.stringify({
      ok: true,
      outcome: "failed_finalized",
      correlation_id: CORR,
      inbox_event_id: INBOX,
      attempt_count: 1,
      error_code: "ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD",
    }),
  );
  assertEquals(r.exitCode, 1);
  assertEquals(r.reason, "failed_finalized");
});

Deno.test("E unknown outcome => failure", () => {
  const r = validateProcessorHttpResponse(
    "200",
    JSON.stringify({ ok: true, outcome: "no_event", correlation_id: CORR }),
  );
  assertEquals(r.exitCode, 1);
});

Deno.test("F malformed JSON => failure", () => {
  const r = validateProcessorHttpResponse("200", "{not-json");
  assertEquals(r.exitCode, 1);
  assertEquals(r.reason, "malformed_json");
});

Deno.test("non-200 => failure", () => {
  const r = validateProcessorHttpResponse(
    "500",
    JSON.stringify({ ok: true, outcome: "disabled", correlation_id: CORR }),
  );
  assertEquals(r.exitCode, 1);
});

// Silence unused ROOT in case path resolution changes.
void ROOT;
