# Security model

## Scope

CampusPass has two security layers with different guarantees:

1. **Local demo:** a front-end flow for demonstrating the product. Its data and access checks are controlled by the same browser that displays the interface.
2. **Production foundation:** Supabase SQL tables, RLS policies, and functions in `supabase/schema.sql`. These are not yet wired to every action in the current UI and do not make the local demo production-ready by themselves.

## Demo data and limits

The demo stores profiles, roll/email mappings, events, holds, bookings, attendee details, payment-review status, QR ticket codes, and check-in status in local storage. A user with browser developer tools can edit those values. There is no server account session in demo mode, no college roster verification, no authoritative shared inventory, no real payment, and no trusted ticket issuer. The `admin` / `admin` credential is public in the source and must only be used for preview.

| Risk | Demo behavior | Production control required |
| --- | --- | --- |
| Roll-number impersonation | Checks `2453` + eight digits and local uniqueness only | Google OAuth plus authoritative roster verification and a unique database constraint |
| Account takeover | Demo sign-in asks for the registered Gmail and roll; neither is proof of identity | Verified OAuth session, recovery controls, rate limits, and server-side ownership checks |
| Admin privilege forgery | Client/local role can be edited | Server-derived role, admin-only policies, and checks on every admin API/function |
| Duplicate/concurrent seat claims | Local storage and optional Web Locks; not shared across devices | Atomic database hold function, unique seat key, lock/transaction, expiry, and server clock |
| Fake payment | Any sample UPI reference can be submitted; admin action is local | Verify actual settlement through the official account or a trusted payment-provider webhook |
| Forged QR | Browser can generate or edit a demo code | High-entropy server-issued random token, hash at rest, protected issuance after approval |
| Copied/replayed QR | Local check-in tracks use only in current browser | Admin-only server verification and atomic one-time redemption, with online scanner state |
| Attendee data edits | Browser can change names/roll numbers after booking | Server validation, immutable approved ticket records, change audit trail |
| Secret leakage | Public anon key placeholders are safe only with RLS; client secrets are not | Keep service-role and signing secrets in server/Edge Function secrets, never `VITE_*` |

## Production ticket lifecycle

1. A trusted booking function validates the authenticated student, event, price, attendees, and live seat holds in one database transaction.
2. Manual payment stays pending until an authorized admin verifies the actual credit; a payment provider could instead verify a signed webhook.
3. A server/Edge Function creates one cryptographically random bearer token per attendee seat. It stores only `SHA-256(token)` in `event_tickets` and returns the raw token only to the authorized ticket owner for QR display.
4. The gate scanner sends the QR token to an authenticated admin endpoint. The `redeem_ticket` function hashes the token, locks the matching row, checks that the booking and payment are approved, and changes `issued` to `redeemed` as one atomic operation.
5. A second concurrent/repeated scan sees `redeemed` and is rejected. Cancelled, unpaid, unknown, wrong-event, or malformed tokens are rejected as well.

The QR must not contain attendee data, a database ID used as authorization, a mutable status flag, or the stored token hash. Consider short-lived tokens or signed online validation if offline gate operation is a requirement; offline devices need a carefully designed synchronization and duplicate-entry policy.

## Current schema boundary

The schema includes `seat_holds`/`hold_seats` for atomic temporary seat claims and `event_tickets`/`redeem_ticket` for production redemption. Production still needs a trusted ticket issuance endpoint, transactional booking creation, payment approval endpoint, roster source, database deployment review, scanner UI, audit logging, rate limits, and end-to-end security checks. The current React UI calls none of those production ticket APIs.

## Operational controls before launch

- Use HTTPS and a verified OAuth provider.
- Configure RLS with least privilege and test student/admin queries as both roles.
- Keep secrets out of the browser and rotate them if exposed.
- Rate-limit login, hold, booking, payment-reference, and scanner endpoints.
- Log admin role changes, payment decisions, ticket issuance, cancellation, and redemption without logging raw bearer tokens.
- Define refunds, pending-payment expiry, cancellation, roster correction, data retention, privacy notice, support, and incident response.
- Test multi-device and simultaneous seat claims; test two simultaneous scans of one ticket; only one should succeed.
