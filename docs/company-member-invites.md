# Company member invites

## Lifecycle vs delivery

Invite **lifecycle** (create → pending → accept / revoke / expire) lives entirely in Postgres RPCs and the Flutter team screens. There is **no email provider** in this step: the app does not send invite emails.

After `create_company_invite`, the API returns the raw `invite_token` **once**. The UI shows it in a copy dialog and clears it from controller state afterward. The token is never listed again and must not be logged.

Delivery of the token to the invitee (email, chat, link) is out of band for Phase 1 Step 15. Accept flow: authenticated user opens `/invites/accept`, pastes the token, and calls `accept_company_invite`.
