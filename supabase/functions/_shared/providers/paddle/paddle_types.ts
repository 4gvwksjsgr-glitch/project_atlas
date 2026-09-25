/**
 * Paddle Billing sandbox adapter types (checkout, subscription GET,
 * next_billed_at preview + update).
 */

export const PADDLE_SANDBOX_BASE_URL = "https://sandbox-api.paddle.com";
export const PADDLE_API_VERSION = "1";
export const PADDLE_REQUEST_TIMEOUT_MS = 10_000;
export const PADDLE_MAX_RESPONSE_BYTES = 256 * 1024;
export const PADDLE_TXN_ID_RE = /^txn_[a-z0-9]+$/i;
/** Matches SQL webhook mapper: ^sub_[a-z0-9]{26}$ */
export const PADDLE_SUBSCRIPTION_ID_RE = /^sub_[a-z0-9]{26}$/;
/** Matches SQL webhook mapper: ^ctm_[a-z0-9]{26}$ */
export const PADDLE_CUSTOMER_ID_RE = /^ctm_[a-z0-9]{26}$/;
/** Matches SQL webhook mapper: ^pri_[a-z0-9]{26}$ */
export const PADDLE_PRICE_ID_RE = /^pri_[a-z0-9]{26}$/;

/** Explicit whitelist of definitive client-rejection HTTP statuses (checkout). */
export const PADDLE_DEFINITIVE_CLIENT_STATUSES = [
  400,
  401,
  403,
  404,
  422,
] as const;

/**
 * Definitive client-rejection statuses for subscription next_billed_at
 * PATCH / preview only. Includes HTTP 409 (Paddle subscription conflicts).
 */
export const PADDLE_DEFINITIVE_SUBSCRIPTION_PATCH_STATUSES = [
  400,
  401,
  403,
  404,
  409,
  422,
] as const;

export interface PaddleCreateCheckoutInput {
  external_price_id: string;
  checkout_page_url: string;
  payment_page_origin: string;
  checkout_path: string;
  company_id: string;
  checkout_session_id: string;
  offer_code: "premium_monthly";
}

export interface PaddleCreateCheckoutSuccess {
  kind: "success";
  external_transaction_id: string;
  checkout_url: string;
}

export interface PaddleCreateCheckoutDefinitiveClientError {
  kind: "definitive_client_error";
  http_status: number;
  sanitized_message: string;
}

export interface PaddleCreateCheckoutUncertain {
  kind: "uncertain";
  reason:
    | "timeout"
    | "network"
    | "http_5xx"
    | "malformed_response"
    | "invalid_checkout_url"
    | "invalid_transaction_id";
  sanitized_message: string;
}

export type PaddleCreateCheckoutResult =
  | PaddleCreateCheckoutSuccess
  | PaddleCreateCheckoutDefinitiveClientError
  | PaddleCreateCheckoutUncertain;

export interface BillingProviderCheckoutAdapter {
  createCheckout(
    input: PaddleCreateCheckoutInput,
  ): Promise<PaddleCreateCheckoutResult>;
}

export interface PaddleTransactionResponse {
  data?: {
    id?: unknown;
    checkout?: {
      url?: unknown;
    } | null;
  } | null;
  error?: {
    detail?: unknown;
    code?: unknown;
  } | null;
}

/** Minimal subscription fields used by D2 reconciliation normalize. */
export interface PaddleSubscriptionItem {
  price?: {
    id?: string | null;
  } | null;
}

export interface PaddleSubscriptionBillingPeriod {
  starts_at?: string | null;
  ends_at?: string | null;
}

export interface PaddleSubscriptionScheduledChange {
  action?: string | null;
}

export interface PaddleSubscriptionData {
  id?: string | null;
  customer_id?: string | null;
  status?: string | null;
  updated_at?: string | null;
  canceled_at?: string | null;
  next_billed_at?: string | null;
  current_billing_period?: PaddleSubscriptionBillingPeriod | null;
  scheduled_change?: PaddleSubscriptionScheduledChange | null;
  items?: PaddleSubscriptionItem[] | null;
}

export interface PaddleSubscriptionResponse {
  data?: PaddleSubscriptionData | null;
  error?: {
    detail?: unknown;
    code?: unknown;
  } | null;
}

/**
 * Deterministic GET /subscriptions/{id} classification for D2.
 * Adapter classifies only; handler decides finalizer later.
 */
export type PaddleGetSubscriptionResult =
  | {
    kind: "success";
    data: PaddleSubscriptionData;
  }
  | {
    kind: "not_found";
    sanitized_message: string;
  }
  | {
    kind: "provider_error";
    reason: "network" | "timeout" | "http_5xx" | "http_non_2xx";
    sanitized_message: string;
  }
  | {
    kind: "invalid_provider_response";
    sanitized_message: string;
  };

export interface BillingProviderSubscriptionReader {
  getSubscription(
    externalSubscriptionId: string,
  ): Promise<PaddleGetSubscriptionResult>;
}

// ---------------------------------------------------------------------------
// PATCH /subscriptions/{id} (+ /preview) — next_billed_at only (Step 18B)
// ---------------------------------------------------------------------------

export interface PaddleUpdateNextBilledAtInput {
  external_subscription_id: string;
  /** RFC3339 UTC timestamp. */
  next_billed_at: string;
  proration_billing_mode: "do_not_bill";
}

/**
 * `http_status: 0` on definitive_client_error means the request was rejected
 * locally (invalid input / missing API key) and was never sent to Paddle.
 */
export type PaddleUpdateSubscriptionResult =
  | {
    kind: "success";
    data: PaddleSubscriptionData;
    next_billed_at: string | null;
    current_period_ends_at: string | null;
  }
  | {
    kind: "definitive_client_error";
    http_status: number;
    sanitized_message: string;
    paddle_error_code?: string | null;
  }
  | {
    kind: "uncertain";
    reason: "timeout" | "network" | "http_5xx" | "malformed_response";
    sanitized_message: string;
  };

export interface PaddleAmountTotals {
  total?: string | null;
  grand_total?: string | null;
}

export interface PaddlePreviewTransaction {
  details?: {
    totals?: PaddleAmountTotals | null;
  } | null;
}

export interface PaddleUpdateSummaryAmount {
  amount?: string | null;
  currency_code?: string | null;
}

export interface PaddleUpdateSummary {
  credit?: PaddleUpdateSummaryAmount | null;
  charge?: PaddleUpdateSummaryAmount | null;
  result?: {
    action?: string | null;
    amount?: string | null;
    currency_code?: string | null;
  } | null;
}

export interface PaddleSubscriptionPreviewData extends PaddleSubscriptionData {
  immediate_transaction?: PaddlePreviewTransaction | null;
  next_transaction?: PaddlePreviewTransaction | null;
  update_summary?: PaddleUpdateSummary | null;
}

export interface PaddleSubscriptionPreviewResponse {
  data?: PaddleSubscriptionPreviewData | null;
  error?: {
    detail?: unknown;
    code?: unknown;
  } | null;
}

/**
 * Fail-closed preview classification. `safe` only when Paddle reports no
 * immediate charge, the previewed next_billed_at equals the requested instant,
 * and update_summary carries no charge.
 */
export type PaddlePreviewNextBilledAtResult =
  | {
    kind: "safe";
    data: PaddleSubscriptionPreviewData;
    preview_next_billed_at: string;
  }
  | {
    kind: "unsafe_immediate_charge";
    sanitized_message: string;
    immediate_grand_total: string | null;
  }
  | {
    kind: "unsafe_unexpected";
    sanitized_message: string;
  }
  | {
    kind: "definitive_client_error";
    http_status: number;
    sanitized_message: string;
    paddle_error_code?: string | null;
  }
  | {
    kind: "uncertain";
    reason: "timeout" | "network" | "http_5xx" | "malformed_response";
    sanitized_message: string;
  };
