/** Atlas Edge Function error contract (schema_version 1). */

export const ERROR_SCHEMA_VERSION = 1 as const;

export type AtlasErrorCode =
  | "ATLAS_METHOD_NOT_ALLOWED"
  | "ATLAS_INVALID_CONTENT_TYPE"
  | "ATLAS_REQUEST_BODY_TOO_LARGE"
  | "ATLAS_INVALID_JSON"
  | "ATLAS_INVALID_REQUEST"
  | "ATLAS_COMPANY_ID_REQUIRED"
  | "ATLAS_IDEMPOTENCY_KEY_REQUIRED"
  | "ATLAS_INVALID_IDEMPOTENCY_KEY"
  | "ATLAS_NOT_AUTHENTICATED"
  | "ATLAS_CORS_ORIGIN_DENIED"
  | "ATLAS_CHECKOUT_IN_PROGRESS"
  | "ATLAS_PROVIDER_OUTCOME_UNKNOWN"
  | "ATLAS_PROVIDER_REQUEST_REJECTED"
  | "ATLAS_CHECKOUT_UNAVAILABLE"
  | "ATLAS_INTERNAL_ERROR"
  | string;

export interface AtlasErrorBody {
  schema_version: typeof ERROR_SCHEMA_VERSION;
  error_code: AtlasErrorCode;
  message: string;
  retryable: boolean;
  correlation_id: string;
}

export class AtlasHttpError extends Error {
  readonly status: number;
  readonly errorCode: AtlasErrorCode;
  readonly retryable: boolean;
  readonly exposeMessage: string;

  constructor(
    status: number,
    errorCode: AtlasErrorCode,
    message: string,
    retryable = false,
  ) {
    super(message);
    this.name = "AtlasHttpError";
    this.status = status;
    this.errorCode = errorCode;
    this.retryable = retryable;
    this.exposeMessage = message;
  }
}

export function atlasErrorBody(
  errorCode: AtlasErrorCode,
  message: string,
  retryable: boolean,
  correlationId: string,
): AtlasErrorBody {
  return {
    schema_version: ERROR_SCHEMA_VERSION,
    error_code: errorCode,
    message,
    retryable,
    correlation_id: correlationId,
  };
}

/** Map Postgres RAISE MESSAGE / PostgREST codes to client error codes. */
export function normalizeRpcErrorCode(raw: string | null | undefined): string {
  if (!raw) return "ATLAS_INTERNAL_ERROR";
  const trimmed = raw.trim();
  if (trimmed.startsWith("ATLAS_")) return trimmed;
  // PostgREST often wraps: "ATLAS_FOO" or longer messages
  const match = trimmed.match(/\b(ATLAS_[A-Z0-9_]+)\b/);
  if (match) return match[1]!;
  return "ATLAS_INTERNAL_ERROR";
}

export function defaultMessageForCode(code: string): string {
  switch (code) {
    case "ATLAS_METHOD_NOT_ALLOWED":
      return "Method not allowed";
    case "ATLAS_INVALID_CONTENT_TYPE":
      return "Content-Type must be application/json";
    case "ATLAS_REQUEST_BODY_TOO_LARGE":
      return "Request body exceeds size limit";
    case "ATLAS_INVALID_JSON":
      return "Request body must be valid JSON";
    case "ATLAS_INVALID_REQUEST":
      return "Invalid request";
    case "ATLAS_COMPANY_ID_REQUIRED":
      return "company_id is required";
    case "ATLAS_IDEMPOTENCY_KEY_REQUIRED":
      return "Idempotency-Key header is required";
    case "ATLAS_INVALID_IDEMPOTENCY_KEY":
      return "Idempotency-Key is invalid";
    case "ATLAS_NOT_AUTHENTICATED":
      return "Authentication required";
    case "ATLAS_CORS_ORIGIN_DENIED":
      return "Origin not allowed";
    case "ATLAS_CHECKOUT_IN_PROGRESS":
      return "Checkout creation already in progress";
    case "ATLAS_PROVIDER_OUTCOME_UNKNOWN":
      return "Provider outcome unknown; do not retry create";
    case "ATLAS_PROVIDER_REQUEST_REJECTED":
      return "Payment provider rejected the checkout request";
    case "ATLAS_CHECKOUT_UNAVAILABLE":
      return "Checkout unavailable";
    case "ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT":
      return "Checkout idempotency conflict";
    case "ATLAS_CHECKOUT_ALREADY_OPEN":
      return "Another checkout session is already open";
    case "ATLAS_CHECKOUT_NOT_ELIGIBLE":
      return "Company is not eligible for checkout";
    case "ATLAS_NOT_COMPANY_MEMBER":
      return "Not a company member";
    case "ATLAS_NOT_COMPANY_OWNER":
      return "Not a company owner";
    case "ATLAS_OFFER_NOT_FOUND":
      return "Offer not found";
    case "ATLAS_PRICE_UNAVAILABLE":
      return "Price unavailable";
    default:
      return "Request failed";
  }
}

export function httpStatusForAtlasCode(code: string): number {
  switch (code) {
    case "ATLAS_METHOD_NOT_ALLOWED":
      return 405;
    case "ATLAS_INVALID_CONTENT_TYPE":
    case "ATLAS_INVALID_JSON":
    case "ATLAS_INVALID_REQUEST":
    case "ATLAS_COMPANY_ID_REQUIRED":
    case "ATLAS_IDEMPOTENCY_KEY_REQUIRED":
    case "ATLAS_INVALID_IDEMPOTENCY_KEY":
      return 400;
    case "ATLAS_REQUEST_BODY_TOO_LARGE":
      return 413;
    case "ATLAS_NOT_AUTHENTICATED":
      return 401;
    case "ATLAS_CORS_ORIGIN_DENIED":
      return 403;
    case "ATLAS_CHECKOUT_IN_PROGRESS":
    case "ATLAS_PROVIDER_OUTCOME_UNKNOWN":
    case "ATLAS_CHECKOUT_ALREADY_OPEN":
    case "ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT":
      return 409;
    case "ATLAS_PROVIDER_REQUEST_REJECTED":
      return 502;
    case "ATLAS_NOT_COMPANY_MEMBER":
    case "ATLAS_NOT_COMPANY_OWNER":
      return 403;
    case "ATLAS_CHECKOUT_NOT_ELIGIBLE":
    case "ATLAS_CHECKOUT_UNAVAILABLE":
    case "ATLAS_OFFER_NOT_FOUND":
    case "ATLAS_PRICE_UNAVAILABLE":
      return 409;
    default:
      return 500;
  }
}

export function retryableForAtlasCode(code: string): boolean {
  return code === "ATLAS_CHECKOUT_IN_PROGRESS";
}
