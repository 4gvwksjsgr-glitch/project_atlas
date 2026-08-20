/** Types for billing-webhook-processor-paddle Edge Function. */

export type EnvReader = (key: string) => string | undefined;

export const PROCESSOR_INVOKE_SECRET_ENV =
  "ATLAS_BILLING_PROCESSOR_INVOKE_SECRET";
export const PROCESSOR_INVOKE_HEADER = "x-atlas-processor-secret";
export const MAX_BATCH_SIZE = 1 as const;
export const PROCESSOR_MAX_BODY_BYTES = 4 * 1024;

export const PROCESSOR_INTERNAL_ERROR = "ATLAS_PROCESSOR_INTERNAL_ERROR";

/** Terminal apply outcomes that finalize inbox without needing fail finalizer. */
export const TERMINAL_APPLY_OUTCOMES = [
  "applied",
  "already_processed",
  "ignored",
  "stale",
] as const;

export type TerminalApplyOutcome = (typeof TERMINAL_APPLY_OUTCOMES)[number];

/** Exact SQL lifecycle status required for each terminal apply outcome. */
export const TERMINAL_APPLY_STATUS_BY_OUTCOME: Record<
  TerminalApplyOutcome,
  "processed" | "ignored"
> = {
  applied: "processed",
  already_processed: "processed",
  ignored: "ignored",
  stale: "ignored",
};

/**
 * Atlas codes emitted by private.apply_paddle_sandbox_webhook_event (14C-2F).
 * Processor fail-finalizer may persist only these exact codes (or INTERNAL).
 */
export const APPROVED_APPLY_ERROR_CODES = [
  "ATLAS_INVALID_REQUEST",
  "ATLAS_INTERNAL_ERROR",
  "ATLAS_SIMULATOR_PROCESSED_INVARIANT",
  "ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING",
  "ATLAS_PROVIDER_EVENT_UNSUPPORTED",
  "ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD",
  "ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA",
  "ATLAS_PROVIDER_LINK_CONFLICT",
  "ATLAS_PROVIDER_EVENT_UNLINKED",
  "ATLAS_PROVIDER_PRICE_MISMATCH",
  "ATLAS_SUBSCRIPTION_NOT_FOUND",
  "ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT",
  "ATLAS_BILLING_NOT_FOUND",
  "ATLAS_PROVIDER_TRIALING_UNSUPPORTED",
  "ATLAS_PROVIDER_PERIOD_INVALID",
  "ATLAS_PROVIDER_STATUS_UNSUPPORTED",
  "ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS",
] as const;

export type ApprovedApplyErrorCode =
  (typeof APPROVED_APPLY_ERROR_CODES)[number];

export type ClaimNextOutcome =
  | "disabled"
  | "empty"
  | "claimed"
  | "reclaimed";

export interface ClaimNextRow {
  outcome: string;
  inbox_event_id: string | null;
  processing_status: string | null;
  attempt_count: number | null;
}

export interface ApplyRow {
  outcome: string;
  inbox_event_id: string | null;
  processing_status: string | null;
  company_id: string | null;
  attempt_count: number | null;
}

export interface FailRow {
  outcome: string;
  inbox_event_id: string | null;
  processing_status: string | null;
  attempt_count: number | null;
}

export interface ProcessorRpcClient {
  claimNextPaddleSandboxWebhookEventServer(): Promise<ClaimNextRow>;
  applyPaddleSandboxWebhookEventServer(
    inboxEventId: string,
  ): Promise<ApplyRow>;
  failPaddleSandboxWebhookEventProcessingServer(
    inboxEventId: string,
    errorCode: string,
  ): Promise<FailRow>;
}

export interface HandlerDeps {
  clock: () => Date;
  uuid: () => string;
  env: EnvReader;
  rpc: ProcessorRpcClient;
  /** Optional override for tests; defaults to crypto.subtle. */
  subtle?: SubtleCrypto;
}

export type ProcessorHttpOutcome =
  | "disabled"
  | "empty"
  | "processed"
  | "failed_finalized";

export interface ProcessorSuccessBody {
  ok: true;
  outcome: ProcessorHttpOutcome;
  correlation_id: string;
  inbox_event_id?: string;
  attempt_count?: number;
  apply_outcome?: string;
  error_code?: string;
}
