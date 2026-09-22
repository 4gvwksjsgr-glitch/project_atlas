# Referrals (Phase 1 Step 17)

## Product rules

- Referral codes are **company-level** (owner manages create / regenerate).
- Public route: `/ref/:code`.
- Pending code is stashed in SharedPreferences (`atlas_pending_referral_code`) across signup/login.
- After authentication, the client calls `claim_referral` when a pending code exists.
- **Qualification** happens server-side when the referred user creates their first company (`create_company` hook). No client entitlement grant.
- Max **5** rewarded referrals per referring company (advisory lock + unique `reward_slot` 1..5).
- Billing classification **B**: rewards are recorded as pending ledger months; provider redemption is deferred. UI copy uses **mesi Premium guadagnati** (never “pagamento annullato”).

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

No client APIs for entitlement redemption or Paddle mutation.
