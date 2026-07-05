# Technical Journal — Serve Invoice PDFs Webhook & End-to-End WhatsApp Delivery

This log documents the debugging process behind Project #1's second workflow
(**Serve Invoice PDFs**) and the final end-to-end integration with the main
**Invoice Automation — WhatsApp Delivery** workflow. It's included deliberately:
the troubleshooting process below reflects the actual day-to-day work of
building automation systems against real, imperfect APIs — and is arguably more
representative of the job than the finished workflow diagram alone.

## Summary

Built a second, stateless n8n workflow (`Serve Invoice PDFs`) whose only job is
to fetch a single invoice PDF from Odoo on demand via a public webhook. This
decouples PDF *generation* from PDF *delivery*: Twilio calls the webhook at
message-send time and always gets a freshly-rendered PDF, rather than n8n
needing to host static files anywhere.

Wired this into the main workflow so that Twilio's WhatsApp API fetches the
invoice PDF live through an ngrok tunnel, completing the full pipeline:

```
Schedule Trigger → Odoo Authenticate → Fetch Unpaid/New Invoices
  → Split Invoice Array → Loop Over Invoices → Get Odoo Session
  → Extract Session ID → Fetch Invoice PDF → Get Customer Contact
  → Merge PDF + Contact → Filter (Has Mobile Number) → Format WhatsApp Number
  → Send via Twilio
```

## Bugs found and fixed (chronological)

### 1. Duplicated protocol/port in n8n's self-reported URL
**Symptom:** Browser showed `DNS_PROBE_FINISHED_NXDOMAIN`; n8n logs showed
`Editor is now accessible via: http://http://localhost:5678:5678`.
**Cause:** Two n8n environment variables (`N8N_HOST` / `WEBHOOK_URL`) each
already contained a full `http://host:port` string, so n8n concatenated them
into a malformed URL. This also caused the container's healthcheck to fail
(`docker ps` showed `unhealthy`).
**Fix:** Ensure `N8N_HOST` is a bare hostname with no protocol/port, and
`WEBHOOK_URL` is the only field carrying the full URL.

### 2. Missing response headers broke session-cookie extraction
**Symptom:** "Extract Session ID" node produced `null`; every downstream
request sent a broken `Cookie: session_id=null` header. Odoo silently
redirected to `/web/login` and returned **HTTP 200** with login-page HTML
instead of an error — so n8n had no way to detect the failure automatically.
**Cause:** The "Get Odoo Session" HTTP Request node wasn't configured to
return response headers, only the JSON body.
**Fix:** Enabled **Options → Response → Include Response Headers and Status
Code**, which exposes `headers['set-cookie']` for the session ID to be
extracted from.

### 3. Malformed Cookie header (duplicate prefix + wrong field reference)
**Symptom:** Same login-redirect behavior even after fix #2.
**Cause:** The header Value field contained a literal, redundant `Cookie:`
prefix (the header **Name** field already supplies that), and referenced a
non-existent field (`session_id` instead of the actual field name
`session_cookie`).
**Fix:** Header Value set to exactly `{{ $json.session_cookie }}` — no manual
prefix, correct field name.

### 4. Wrong Odoo report technical name
**Symptom:** Odoo returned `403 Forbidden — perhaps check your credentials?`
even with a valid session cookie.
**Cause:** The workflow used `account.report_invoice`, which does not exist
as a registered report action in this Odoo 17 instance. The correct
technical name is **`account.report_invoice_with_payments`** — a naming
change from older Odoo versions (12–14 commonly used `report_invoice`).
**Fix:** Updated the report URL in both the Serve Invoice PDFs workflow and
the main workflow's Fetch Invoice PDF node.
**Lesson:** A confirmed valid session + a wrong report name still produces a
403, not a clear "report not found" error — worth checking report names
directly against Odoo's `ir.actions.report` model when this happens, rather
than assuming it's an auth problem.

### 5. Odoo UI permission dropdown didn't sync to the real access-control group
**Symptom:** `Fetch Unpaid/New Invoices` failed with
`odoo.exceptions.AccessError: You are not allowed to access 'Journal Entry'
(account.move) records`, even though the authenticating user (Mitchell
Admin, uid 2) showed **"Billing Administrator"** selected in
Settings → Users → Access Rights.
**Cause:** The friendly dropdown selection had not actually been committed to
the user's real `res.groups` membership. Checking the user's raw technical
groups (Developer Mode → Users & Companies → Groups) confirmed
`Invoicing / Billing Administrator` was genuinely absent from the list,
despite the UI implying otherwise.
**Fix:** Opened the **group record itself** (Settings → Users & Companies →
Groups → "Invoicing / Billing Administrator") and added the user directly
from that side, rather than via the user form's dropdown. This forced the
underlying relation to commit correctly.
**Lesson:** When an Odoo API call is rejected despite the UI showing correct
permissions, verify the user's actual group membership directly — the
simplified Access Rights dropdown can visually desync from the backing data.

### 6. IF node "is not empty" check broken by boolean field values
**Symptom:** `Filter - Has Mobile Number` node errored:
`Wrong type: 'false' is a boolean but was expecting a string`.
**Cause:** Odoo represents an empty field as the boolean `false`, not `null`
or `""`. n8n's strict-mode string comparison rejected the type mismatch.
**Partial fix (introduced a second bug):** Enabling "Convert types where
required" resolved the type error, but caused n8n to coerce the boolean
`false` into the *string* `"false"` before the emptiness check — and a
5-character string is not empty, so contacts with no real mobile number
incorrectly passed the filter.
**Final fix:** Explicit expression to normalize Odoo's `false` placeholder to
a real empty string before the check:
```
{{ $json.result[0].mobile && $json.result[0].mobile !== false ? $json.result[0].mobile : '' }}
```
**Lesson:** Odoo's JSON-RPC layer uses `false` as a universal "no value"
sentinel across field types (not just booleans) — any filter logic touching
raw Odoo field values needs to account for this explicitly.

### 7. Twilio WhatsApp Sandbox — join expiry
**Symptom:** Message API call succeeded (`status: "queued"`, PDF media
attached correctly) but never arrived on WhatsApp. Twilio's message log
showed **Error 63015**: *"Channel Sandbox can only send messages to phone
numbers that have joined the Sandbox."*
**Cause:** Twilio's WhatsApp Sandbox requires recipients to periodically
re-send a `join <keyword>` message; the connection lapses after a period of
inactivity.
**Fix:** Recipient re-sent the join code to the sandbox number.

### 8. Twilio trial-account daily message cap
**Symptom:** After rejoining the sandbox, the next send attempt returned
`The service is receiving too many requests from you — exceeded the 5 daily
messages limit`.
**Cause:** Twilio trial (non-upgraded) accounts are capped at 5 outbound
messages/day as an anti-abuse measure — a hard account-tier limit, unrelated
to the workflow itself.
**Status:** Confirmed as the final blocker; workflow build is functionally
complete. Awaiting daily reset (or account upgrade) to capture a final
successful delivery screenshot.

## Environment / operational notes

- **ngrok free tier**: session must stay running in its own terminal for the
  tunnel to stay reachable — if the terminal closes or the machine sleeps,
  the tunnel drops even though the static domain persists across restarts.
- **n8n webhook test vs. production URLs**: the Test URL (`/webhook-test/...`)
  only fires once per "Execute workflow" click and only while the canvas is
  open; the Production URL (`/webhook/...`) requires the workflow to be
  **Published/Active** and works continuously — this is what any real
  external caller (Twilio, etc.) must use.
- **git credential helper**: Windows Git's deprecated `manager-core` helper
  name was replaced with `manager` to fix push authentication.
- **`.gitignore`**: added `n8n_files/` to exclude Docker volume runtime data
  (may contain encrypted credentials/session state) from version control.

## Architecture decision: stateless webhook over disk-based PDF storage

Early in Project #1, a disk-write approach (saving PDFs to a shared Docker
volume, then referencing the file path) was abandoned after persistent
`fs.access()` false-negative behavior on Windows Docker volumes. The
**Serve Invoice PDFs** webhook workflow replaces this entirely: Twilio's
`media_url` points at a public endpoint that authenticates to Odoo and
renders the requested invoice fresh, on every call. This trades a small
amount of per-request latency for a much simpler, more resilient design with
no file-system state to manage or go stale.
