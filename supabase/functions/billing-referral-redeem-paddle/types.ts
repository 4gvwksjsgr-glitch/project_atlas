/** Types for billing-referral-redeem-paddle. */

import type {
  PaddleGetSubscriptionResult,
  PaddlePreviewNextBilledAtResult,
  PaddleUpdateNextBilledAtInput,
  PaddleUpdateSubscriptionResult,
} from "../_shared/providers/paddle/paddle_types.ts";

export type EnvReader = (key: string) => string | undefined;

export const REDEEM_INVOKE_SECRET_ENV = "ATLAS_REFERRAL_REDEEM_INVOKE_SECRET";
export const REDEEM_INVOKE_HEADER = "x-atlas-referral-redeem-secret";
export const REDEEM_MAX_BODY_BYTES = 4 * 1024;

export interface ClaimRedemptionRow {
  outcome: string;
  operation_id: string | null;
  reward_count: number | null;
  reward_ids: string[] | null;
  expected_old_next_billed_at: string | null;
  target_next_billed_at: string | null;
  provider_subscription_id: string | null;
  operation_status: string | null;
  error_code: string | null;
}

export interface OpenRedemptionRow {
  id: string;
  company_id: string;
  status: string;
  reward_count: number;
  reward_ids: string[];
  expected_old_next_billed_at: string | null;
  target_next_billed_at: string | null;
  provider_subscription_id_snapshot: string | null;
  last_error_code: string | null;
  attempt_count: number;
}

export interface ConfirmRedemptionRow {
  outcome: string;
  operation_id: string | null;
  rewards_redeemed: number | null;
  error_code: string | null;
}

export interface ReferralRedeemRpcClient {
  claimReferralRedemptionOperationServer(
    companyId: string,
  ): Promise<ClaimRedemptionRow>;
  updateReferralRedemptionOperationStatusServer(args: {
    operation_id: string;
    status: string;
    error_code?: string | null;
    set_previewed?: boolean;
    set_provider_accepted?: boolean;
    bump_attempt?: boolean;
    expected_old?: string | null;
    target?: string | null;
    subscription_snapshot?: string | null;
  }): Promise<boolean>;
  confirmReferralRedemptionOperationServer(args: {
    company_id: string;
    observed_next_billed_at?: string | null;
    provider_subscription_id?: string | null;
  }): Promise<ConfirmRedemptionRow>;
  abortReferralRedemptionOperationServer(
    operationId: string,
    errorCode: string,
  ): Promise<boolean>;
  getOpenReferralRedemptionOperationServer(
    companyId: string,
  ): Promise<OpenRedemptionRow | null>;
}

export interface ReferralRedeemPaddleClient {
  getSubscription(id: string): Promise<PaddleGetSubscriptionResult>;
  previewNextBilledAt(
    input: PaddleUpdateNextBilledAtInput,
  ): Promise<PaddlePreviewNextBilledAtResult>;
  updateNextBilledAt(
    input: PaddleUpdateNextBilledAtInput,
  ): Promise<PaddleUpdateSubscriptionResult>;
}

export interface HandlerDeps {
  fetch: typeof fetch;
  clock: () => Date;
  env: EnvReader;
  rpc: ReferralRedeemRpcClient;
  paddle: ReferralRedeemPaddleClient;
}
