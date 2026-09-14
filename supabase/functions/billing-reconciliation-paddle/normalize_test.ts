/**
 * Snapshot normalize + prepare binding tests (D2-A).
 */

import { assertEquals } from "@std/assert";
import {
  assertPrepareProviderBinding,
  normalizePaddleSubscriptionData,
} from "./normalize.ts";

const SUB = "sub_01h4examplesubid0000000001";
const CTM = "ctm_01h4examplecustid000000001";
const PRI = "pri_01h4examplepriceid00000001";
const UPDATED = "2026-09-14T10:00:00.000Z";
const PERIOD_START = "2026-09-01T00:00:00.000Z";
const PERIOD_END = "2026-10-01T00:00:00.000Z";

function baseData(overrides: Record<string, unknown> = {}) {
  return {
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
  };
}

Deno.test("normalize active / past_due / paused / trialing valid", () => {
  for (const status of ["active", "past_due", "paused", "trialing"]) {
    const r = normalizePaddleSubscriptionData(baseData({ status }));
    assertEquals(r.ok, true);
    if (r.ok) {
      assertEquals(r.snapshot.provider_subscription_status, status);
      assertEquals(r.snapshot.external_price_id, PRI);
      assertEquals(r.snapshot.cancel_at_period_end, false);
    }
  }
});

Deno.test("normalize canceled with and without canceled_at", () => {
  const withAt = normalizePaddleSubscriptionData(baseData({
    status: "canceled",
    canceled_at: "2026-09-13T12:00:00.000Z",
  }));
  assertEquals(withAt.ok, true);
  if (withAt.ok) {
    assertEquals(withAt.snapshot.canceled_at, "2026-09-13T12:00:00.000Z");
  }

  const withoutAt = normalizePaddleSubscriptionData(baseData({
    status: "canceled",
    canceled_at: null,
  }));
  assertEquals(withoutAt.ok, true);
  if (withoutAt.ok) {
    assertEquals(withoutAt.snapshot.canceled_at, null);
  }
});

Deno.test("normalize scheduled cancel flag", () => {
  const yes = normalizePaddleSubscriptionData(baseData({
    scheduled_change: { action: "cancel" },
  }));
  assertEquals(yes.ok, true);
  if (yes.ok) assertEquals(yes.snapshot.cancel_at_period_end, true);

  const no = normalizePaddleSubscriptionData(baseData({
    scheduled_change: { action: "pause" },
  }));
  assertEquals(no.ok, true);
  if (no.ok) assertEquals(no.snapshot.cancel_at_period_end, false);

  const none = normalizePaddleSubscriptionData(baseData({
    scheduled_change: null,
  }));
  assertEquals(none.ok, true);
  if (none.ok) assertEquals(none.snapshot.cancel_at_period_end, false);
});

Deno.test("normalize rejects missing/invalid id status updated_at price", () => {
  assertEquals(
    normalizePaddleSubscriptionData(baseData({ id: "" })).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(baseData({ id: "sub_short" })).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(baseData({ status: "  " })).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(baseData({ updated_at: null })).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(baseData({ updated_at: "not-a-date" }))
      .ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(baseData({ items: [] })).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(
      baseData({ items: [{ price: { id: "bad" } }] }),
    ).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(
      baseData({
        current_billing_period: { starts_at: "nope", ends_at: PERIOD_END },
      }),
    ).ok,
    false,
  );
  assertEquals(
    normalizePaddleSubscriptionData(
      baseData({ canceled_at: "not-a-ts" }),
    ).ok,
    false,
  );
});

Deno.test("prepare binding requires exact sub and customer match", () => {
  const snap = normalizePaddleSubscriptionData(baseData());
  assertEquals(snap.ok, true);
  if (!snap.ok) return;

  assertEquals(
    assertPrepareProviderBinding(
      {
        external_subscription_id: SUB,
        external_customer_id: CTM,
      },
      snap.snapshot,
    ).ok,
    true,
  );

  const badSub = assertPrepareProviderBinding(
    {
      external_subscription_id: "sub_01h4examplesubid0000000099",
      external_customer_id: CTM,
    },
    snap.snapshot,
  );
  assertEquals(badSub.ok, false);
  if (!badSub.ok) {
    assertEquals(badSub.classification, "invalid_provider_response");
    assertEquals(badSub.reason, "subscription_id_mismatch");
  }

  const badCtm = assertPrepareProviderBinding(
    {
      external_subscription_id: SUB,
      external_customer_id: "ctm_01h4examplecustid000000099",
    },
    snap.snapshot,
  );
  assertEquals(badCtm.ok, false);
  if (!badCtm.ok) {
    assertEquals(badCtm.classification, "invalid_provider_response");
    assertEquals(badCtm.reason, "customer_id_mismatch");
  }
});
