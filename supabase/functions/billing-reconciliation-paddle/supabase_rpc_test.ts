// deno-lint-ignore-file require-await
/**
 * Billing reconciliation RPC client tests — injected Supabase stub only.
 */

import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { AtlasHttpError } from "../_shared/errors.ts";
import { createRpcClientFromSupabase } from "./supabase_rpc.ts";
import {
  RECONCILIATION_FINALIZER_RESULTS,
  type ReconciliationFinalizerResult,
} from "./types.ts";

type RpcCall = { name: string; args: Record<string, unknown> };

function stubClient(
  handler: (
    name: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: { message: string } | null }>,
): { client: SupabaseClient; calls: RpcCall[] } {
  const calls: RpcCall[] = [];
  const client = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return await handler(name, args);
    },
  } as unknown as SupabaseClient;
  return { client, calls };
}

const COMPANY = "11111111-1111-4111-8111-111111111111";
const ACTOR = "22222222-2222-4222-8222-222222222222";

Deno.test("prepare RPC uses exact name and argument keys", async () => {
  const { client, calls } = stubClient(async () => ({
    data: [{
      company_id: COMPANY,
      provider_code: "paddle",
      provider_environment: "test",
      external_subscription_id: "sub_01h4examplesubid0000000001",
      external_customer_id: "ctm_01h4examplecustid000000001",
      external_price_id: "pri_01h4examplepriceid00000001",
      expected_webhook_watermark: null,
      expected_provider_state_version: null,
      expected_linkage_fingerprint: "link_fp",
      expected_local_state_fingerprint: "local_fp",
    }],
    error: null,
  }));
  const rpc = createRpcClientFromSupabase(client);
  const row = await rpc.prepareCompanyBillingReconciliationServer({
    company_id: COMPANY,
    actor_user_id: ACTOR,
  });
  assertEquals(calls.length, 1);
  assertEquals(calls[0]!.name, "prepare_company_billing_reconciliation_server");
  assertEquals(calls[0]!.args, {
    p_company_id: COMPANY,
    p_actor_user_id: ACTOR,
  });
  assertEquals(row.external_subscription_id, "sub_01h4examplesubid0000000001");
});

Deno.test("apply RPC passes all expected argument keys once", async () => {
  const { client, calls } = stubClient(async () => ({
    data: [{
      result: "updated",
      company_id: COMPANY,
      provider_updated_at: "2026-09-14T10:00:00.000Z",
    }],
    error: null,
  }));
  const rpc = createRpcClientFromSupabase(client);
  await rpc.applyCompanyBillingReconciliationServer({
    company_id: COMPANY,
    actor_user_id: ACTOR,
    expected_external_subscription_id: "sub_01h4examplesubid0000000001",
    expected_external_customer_id: "ctm_01h4examplecustid000000001",
    expected_linkage_fingerprint: "link_fp",
    external_price_id: "pri_01h4examplepriceid00000001",
    provider_subscription_status: "active",
    current_period_start: "2026-09-01T00:00:00.000Z",
    current_period_end: "2026-10-01T00:00:00.000Z",
    cancel_at_period_end: false,
    canceled_at: null,
    provider_updated_at: "2026-09-14T10:00:00.000Z",
  });
  assertEquals(calls.length, 1);
  assertEquals(calls[0]!.name, "apply_company_billing_reconciliation_server");
  assertEquals(calls[0]!.args, {
    p_company_id: COMPANY,
    p_actor_user_id: ACTOR,
    p_expected_external_subscription_id: "sub_01h4examplesubid0000000001",
    p_expected_external_customer_id: "ctm_01h4examplecustid000000001",
    p_expected_linkage_fingerprint: "link_fp",
    p_external_price_id: "pri_01h4examplepriceid00000001",
    p_provider_subscription_status: "active",
    p_current_period_start: "2026-09-01T00:00:00.000Z",
    p_current_period_end: "2026-10-01T00:00:00.000Z",
    p_cancel_at_period_end: false,
    p_canceled_at: null,
    p_provider_updated_at: "2026-09-14T10:00:00.000Z",
  });
});

Deno.test("finalizer RPC restricted to exactly three result values", async () => {
  assertEquals(RECONCILIATION_FINALIZER_RESULTS.length, 3);
  assertEquals(
    [...RECONCILIATION_FINALIZER_RESULTS].sort(),
    ["invalid_provider_response", "not_found", "provider_error"],
  );

  for (const result of RECONCILIATION_FINALIZER_RESULTS) {
    const { client, calls } = stubClient(async () => ({
      data: [{ result, company_id: COMPANY, recorded: true }],
      error: null,
    }));
    const rpc = createRpcClientFromSupabase(client);
    await rpc.recordCompanyBillingReconciliationResultServer({
      company_id: COMPANY,
      actor_user_id: ACTOR,
      expected_external_subscription_id: "sub_01h4examplesubid0000000001",
      expected_external_customer_id: "ctm_01h4examplecustid000000001",
      expected_linkage_fingerprint: "link_fp",
      result,
      error_sanitized: "x",
      provider_updated_at: null,
    });
    assertEquals(calls.length, 1);
    assertEquals(
      calls[0]!.name,
      "record_company_billing_reconciliation_result_server",
    );
    assertEquals(calls[0]!.args.p_result, result);
  }
});

Deno.test("finalizer rejects non-allowlisted result before RPC", async () => {
  let rpcInvoked = 0;
  const { client } = stubClient(async () => {
    rpcInvoked += 1;
    return { data: [], error: null };
  });
  const rpc = createRpcClientFromSupabase(client);
  await assertRejects(
    () =>
      rpc.recordCompanyBillingReconciliationResultServer({
        company_id: COMPANY,
        actor_user_id: ACTOR,
        expected_external_subscription_id: "sub_01h4examplesubid0000000001",
        expected_external_customer_id: "ctm_01h4examplecustid000000001",
        expected_linkage_fingerprint: "link_fp",
        // Force invalid for runtime guard (compile-time union excludes this).
        result: "updated" as unknown as ReconciliationFinalizerResult,
        error_sanitized: null,
        provider_updated_at: null,
      }),
    AtlasHttpError,
  );
  assertEquals(rpcInvoked, 0);
});

Deno.test("RPC Atlas error preserved; unknown sanitized; no retry", async () => {
  const { client, calls } = stubClient(async () => ({
    data: null,
    error: { message: "ATLAS_NOT_COMPANY_OWNER" },
  }));
  const rpc = createRpcClientFromSupabase(client);
  const err = await assertRejects(
    () =>
      rpc.prepareCompanyBillingReconciliationServer({
        company_id: COMPANY,
        actor_user_id: ACTOR,
      }),
    AtlasHttpError,
  ) as AtlasHttpError;
  assertEquals(err.errorCode, "ATLAS_NOT_COMPANY_OWNER");
  assertEquals(err.status, 403);
  assertEquals(err.retryable, false);
  assertEquals(calls.length, 1);

  const { client: client2, calls: calls2 } = stubClient(async () => ({
    data: null,
    error: { message: "connection reset by peer" },
  }));
  const rpc2 = createRpcClientFromSupabase(client2);
  const err2 = await assertRejects(
    () =>
      rpc2.prepareCompanyBillingReconciliationServer({
        company_id: COMPANY,
        actor_user_id: ACTOR,
      }),
    AtlasHttpError,
  ) as AtlasHttpError;
  assertEquals(err2.errorCode, "ATLAS_INTERNAL_ERROR");
  assertEquals(calls2.length, 1);
});
