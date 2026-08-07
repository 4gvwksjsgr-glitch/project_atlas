/** Types for billing-checkout-create Edge Function. */

import type { AuthUserLookup } from "../_shared/auth.ts";
import type { BillingProviderCheckoutAdapter } from "../_shared/providers/paddle/paddle_types.ts";

export const OFFER_CODE = "premium_monthly" as const;
export const EXPECTED_PROVIDER_CODE = "paddle" as const;
export const EXPECTED_PROVIDER_ENVIRONMENT = "test" as const;

export interface ReserveBillingCheckoutSessionRow {
  session_id: string;
  reuse: boolean;
  provider_environment: string;
  billing_provider_price_id: string;
  external_price_id: string;
  atlas_plan_code: string;
  offer_code: string;
  checkout_status: string;
  provider_create_status: string;
  return_token_plain: string;
  return_token_version: number;
  expires_at: string;
  existing_checkout_url: string | null;
  existing_external_transaction_id: string | null;
  provider_code: string;
  payment_page_origin: string;
  checkout_path: string;
  return_path: string;
  checkout_page_url: string;
}

export interface AttachBillingCheckoutProviderResultRow {
  applied: boolean;
  session_id: string;
  provider_create_status: string | null;
  checkout_status: string | null;
}

export interface BillingCheckoutRpcClient {
  reserveBillingCheckoutSessionServer(args: {
    company_id: string;
    actor_user_id: string;
    offer_code: string;
    idempotency_key: string;
    now?: string;
  }): Promise<ReserveBillingCheckoutSessionRow>;

  attachBillingCheckoutProviderResultServer(args: {
    session_id: string;
    actor_user_id: string;
    expected_from: string;
    to_status: string;
    external_transaction_id?: string | null;
    checkout_url?: string | null;
    error_sanitized?: string | null;
    now?: string;
  }): Promise<AttachBillingCheckoutProviderResultRow>;
}

export type EnvReader = (key: string) => string | undefined;

export interface HandlerDeps {
  fetch: typeof fetch;
  clock: () => Date;
  uuid: () => string;
  authLookup: AuthUserLookup;
  rpc: BillingCheckoutRpcClient;
  paddle: BillingProviderCheckoutAdapter;
  corsAllowlist: readonly string[];
  env: EnvReader;
}

export interface CheckoutCreateSuccessBody {
  schema_version: 1;
  checkout_session_id: string;
  checkout_url: string;
  return_token: string;
  return_token_version: number;
  expires_at: string;
  reused: boolean;
}
