/** Paddle Billing sandbox checkout adapter types. */

export const PADDLE_SANDBOX_BASE_URL = "https://sandbox-api.paddle.com";
export const PADDLE_API_VERSION = "1";
export const PADDLE_REQUEST_TIMEOUT_MS = 10_000;
export const PADDLE_MAX_RESPONSE_BYTES = 256 * 1024;
export const PADDLE_TXN_ID_RE = /^txn_[a-z0-9]+$/i;

/** Explicit whitelist of definitive client-rejection HTTP statuses. */
export const PADDLE_DEFINITIVE_CLIENT_STATUSES = [
  400,
  401,
  403,
  404,
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
