/** Types for billing-webhook-paddle Edge Function. */

export type EnvReader = (key: string) => string | undefined;

export const WEBHOOK_MAX_BODY_BYTES = 256 * 1024;
export const WEBHOOK_SIGNATURE_TOLERANCE_SECONDS = 5;
export const WEBHOOK_SECRET_ENV = "PADDLE_SANDBOX_WEBHOOK_SECRET";

/** Sandbox/test only: live `evt_` plus Paddle Simulator `ntfsimevt_`. */
export const PADDLE_EVENT_ID_RE = /^(?:evt|ntfsimevt)_[a-z\d]{26}$/;
export const PADDLE_SUBSCRIPTION_ID_RE = /^sub_[a-z\d]{26}$/;

export const SUPPORTED_EVENT_TYPES = [
  "subscription.created",
  "subscription.updated",
  "subscription.activated",
  "subscription.canceled",
  "subscription.past_due",
  "transaction.completed",
] as const;

export type SupportedEventType = (typeof SUPPORTED_EVENT_TYPES)[number];

export type EventClassification = "supported" | "ignored";

export interface IngestPaddleSandboxWebhookEventRow {
  outcome: "inserted" | "duplicate";
  inbox_event_id: string;
}

export interface IngestPaddleSandboxWebhookEventArgs {
  external_event_id: string;
  event_type: string;
  provider_created_at: string;
  payload_hash: string;
  payload_json: Record<string, unknown>;
  classification: EventClassification;
  external_subscription_id?: string | null;
}

export interface BillingWebhookRpcClient {
  ingestPaddleSandboxWebhookEventServer(
    args: IngestPaddleSandboxWebhookEventArgs,
  ): Promise<IngestPaddleSandboxWebhookEventRow>;
}

export interface HandlerDeps {
  clock: () => Date;
  uuid: () => string;
  env: EnvReader;
  rpc: BillingWebhookRpcClient;
  /** Optional override for tests; defaults to crypto.subtle. */
  subtle?: SubtleCrypto;
}

export interface VerifiedWebhookPayload {
  event_id: string;
  event_type: string;
  occurred_at: string;
  classification: EventClassification;
  external_subscription_id: string | null;
  payload_json: Record<string, unknown>;
}
