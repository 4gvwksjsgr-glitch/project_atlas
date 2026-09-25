# Referrals (Phase 1 Step 17)

## Product rules

- Referral codes are **company-level** (owner manages create / regenerate).
- Public route: `/ref/:code`.
- Pending code is stashed in SharedPreferences (`atlas_pending_referral_code`) across signup/login.
- After authentication, the client calls `claim_referral` when a pending code exists.
- **Qualification** happens server-side when the referred user creates their first company (`create_company` hook). No client entitlement grant.
- Max **5** rewarded referrals per referring company (advisory lock + unique `reward_slot` 1..5).
- Billing classification **B**: rewards are recorded as ledger months; **provider redemption** is implemented in Step 18B (`docs/referral-redemption.md`) via Paddle `next_billed_at` + `do_not_bill`, gated by `referral_redemption_enabled` (default **false**). Trigger model is **AUTO** after authoritative subscription apply (processor/reconcile → evaluate → redeem Edge); UI copy uses **mesi Premium** status lines (never “pagamento annullato” until confirmed).

## Anti-abuse

- **Self-referral:** any *current member* of the referring company cannot claim that company’s code (not only the owner).
- **Late claim:** users who already own a company cannot claim (`ATLAS_REFERRAL_CLAIM_WINDOW_CLOSED`).
- **One referrer:** unique `referrals.referred_user_id`; repeated claim is idempotent.
- **Code rotation:** regenerate revokes the previous active code immediately; already-claimed referrals and earned rewards remain.
- Referral codes are **share tokens**, not auth credentials (plaintext URL-safe storage is intentional).

## Privacy

- Owner overview: link + `rewarded_count`/`max_rewards` + history rows labeled **Amico iscritto** (no email).
- Non-owner members: counts only (`is_owner=false`, `code=null`, empty history) — enforced in RPC, not only UI.
- No anonymous server lookup of company identity for `/ref/:code` (client stashes code until authenticated claim).

## RPCs

| RPC | Who |
|-----|-----|
| `get_or_create_company_referral_link` | owner |
| `regenerate_company_referral_link` | owner |
| `claim_referral` | authenticated, before first owned company |
| `get_referral_overview` | any company member |
| `retry_referral_redemption` | owner (heal/claim only; never chooses months/dates) |

Client never calls Paddle. Redemption mutation is server-only (`billing-referral-redeem-paddle`) when the kill switch is enabled.
