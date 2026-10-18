# CampusPass: presentation guide

Use this guide to explain the project in a demo or judging round. Be precise about what is implemented in the local prototype and what still needs a production backend.

## 45-second introduction

> CampusPass is a college event booking prototype. It gives students one place to discover campus events, select seats, enter attendee details for a group, and follow a manual payment-review flow. Admins get a separate dashboard to publish events and review demo payment references. I focused on the booking journey and on the problems that appear around temporary seat holds, student identity, group attendees, and duplicate tickets. The current version is a local demo; I also prepared a Supabase schema that shows how the production security boundary should work.

If asked about development process, describe it truthfully. For this project, the requirements and product flow were developed with AI coding assistance. Explain the parts you reviewed and understand rather than claiming that every line was typed manually.

## Walkthrough order

1. **Start at the login screen.** Show the separate student and admin entry points. In demo mode, create a student profile using an email and a roll number in the format `2453` plus eight digits.
2. **Show return access.** Sign out, choose **Student sign in**, switch to **Already registered? Sign in**, and use the same Gmail and roll number. The demo browser restores that student's saved booking list.
3. **Discover an event.** Search or open an event card. Explain that the seat map uses rows and labels, and the demo temporarily holds selected seats for two minutes.
4. **Book several seats.** Pick two or three seats and continue. Show the attendee fields. Each seat must have a name and a different valid roll number.
5. **Explain payment honestly.** Paid events accept a sample UPI reference and wait for admin review. The prototype does not collect or verify real money.
6. **Open the admin desk.** Use the demo credentials `admin` / `admin`. Show a pending booking, check the attendee information, and mark the demo payment received.
7. **Return to the student tickets page.** Show one QR per attendee/seat. The QR and check-in are demo-only. In the admin desk, scan with a keyboard-wedge QR scanner or paste the QR content into the demo check-in field; a repeat check-in is rejected in the same browser.

## How the app is built

- **React** builds reusable screens and updates the page as app state changes.
- **Vite** runs the local development server and creates the production bundle.
- **CSS** controls layout, responsive behavior, event cards, seat states, forms, and ticket details.
- **Lucide React** supplies interface icons.
- **qrcode.react** renders the QR graphic from each demo ticket code.
- **Browser local storage** persists demo profiles, event changes, bookings, holds, and ticket status in one browser. It is useful for a preview, but it is editable by the user and is not a database security boundary.
- **Supabase schema** describes a future server-backed setup: authenticated profiles, admin roles, RLS policies, event/seat data, temporary holds, bookings, payment records, per-seat ticket records, and one-time ticket redemption.

## Main data and flow

### Student identity

The form checks that a roll number is twelve digits total and starts with `2453`. A unique mapping prevents two demo profiles from claiming the same roll number inside the same browser. That does not prove a student is enrolled. Production must use Google OAuth and compare the roll number with a college-controlled roster.

### Seat booking

The UI holds selected seats for two minutes. A timer shows the remaining time, and expired holds are removed. The demo tries to coordinate tabs using the browser's Web Locks API, with local storage as its persistence. Different devices and browsers are not coordinated. In production, a database transaction and unique constraints must decide which student gets the seat.

### Group attendees

The booking is one purchase with one attendee record per seat. At checkout, each attendee gets a name and roll number. This makes the ticket list and admin review identify the person assigned to each seat rather than just the student who submitted the booking.

### Payment and ticket issuance

Paid bookings stay pending until the admin approves the sample reference. On approval, the demo generates a random code per attendee and renders it as a QR. Free bookings are marked confirmed immediately. A QR picture is only a way to carry a token; a QR by itself does not prove that a ticket is genuine.

### Entry check-in

The demo check-in looks up the code in local browser data and marks it used, so a second scan in that browser is rejected. A person can edit the same local data or use a second device, so this is a demonstration of the flow, not fraud prevention. The production design stores only a hash of a server-issued token and uses the admin-only `redeem_ticket` RPC to validate and consume it once.

## Likely judge questions

### What problem does this solve?

College event sign-ups are often spread across messages and forms. CampusPass combines event discovery, a seat map, attendee details, payment review, and ticket presentation in one journey.

### What happens if two students select the same seat?

In this demo, holds are local to one browser and may coordinate same-browser tabs when Web Locks is available. That is not enough for an actual event. The production schema uses an atomic seat-hold function and a primary key on event plus seat so concurrent database claims cannot both win.

### Can a student fake a college roll number?

Yes, in demo mode. The app only checks the format and local uniqueness. Production needs authenticated Google accounts and an authoritative roster check, ideally before booking.

### Can someone forge a QR ticket?

Yes, in the demo, because the browser creates and stores the ticket code. The visible QR is clearly marked as demo-only. Production must issue a high-entropy token from a trusted server after payment approval, store only its hash, and validate it online at the gate. The server must reject a used, unpaid, cancelled, or unknown token.

### Can a screenshot be used twice?

The local demo rejects repeat check-in only in the same browser storage. Production's admin scanner must call a server-side atomic redemption operation so simultaneous scans cannot both succeed.

### Does the app charge money?

No. It collects a sample UPI reference for a manual review demonstration. A real college must configure its receiving UPI account and verify the credit in its account before approving the booking. Payment processing and operational fees depend on the chosen services.

### Is `admin` / `admin` secure?

No. Those are requested demo credentials and are hard-coded. They must never be used in a live service. In production, the server checks a trusted admin role stored in the database and protects every admin operation with row-level security or an authenticated server function.

### What does the Supabase schema do today?

It is a security foundation and design artifact. The current booking UI still uses local storage and does not call the production booking, payment, ticket issuance, or redemption APIs. Do not present those paths as production-ready.

### What would you build next?

Connect Google OAuth, validate students against the college roster, wire transactional booking/seat-hold APIs, verify UPI payments securely, issue server-side ticket tokens, build an authenticated QR scanner, and add automated tests for concurrent holds, role boundaries, payment approval, and one-time redemption.

## Source map for the demo

- `src/App.jsx`: app state, authentication/demo paths, seats, checkout, tickets, admin review, QR rendering, and demo check-in.
- `src/style.css`: responsive design and component states.
- `src/main.jsx`: React entry point.
- `supabase/schema.sql`: future database constraints, RLS policies, hold function, and redemption function.
- `README.md`: setup, features, architecture, and production checklist.

## Before the presentation

- Run `npm run build` to confirm the app compiles.
- Run `npm run build:portable` if you will present from the standalone preview.
- Use sample student data only; do not put real student details or payment references into the demo.
- Practice one complete path: register student, select multiple seats, submit demo payment, approve as admin, return as student, show QR, and repeat-check-in.
- State the local-storage and QR security limitations before a judge has to discover them.
