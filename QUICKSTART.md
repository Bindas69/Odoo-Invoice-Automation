# Quick Start Guide: Odoo Invoice Automation

Get the actual working system running. This deploys **two n8n workflows**, not one — the second is what makes WhatsApp delivery possible at all, so don't skip it.

---

## ✅ Pre-Flight Checklist

- [ ] Docker Desktop installed and running
- [ ] A Twilio account with WhatsApp Sandbox enabled
- [ ] A phone that has joined your Twilio WhatsApp sandbox (send the `join <code>` message once)
- [ ] An ngrok account (free tier works)
- [ ] This repository cloned to your machine

---

## Step 1: Clone and Configure (5 minutes)

```bash
git clone https://github.com/Bindas69/Odoo-Invoice-Automation.git
cd Odoo-Invoice-Automation
cp .env.example .env
```

Edit `.env`:
```env
ODOO_USER=admin
ODOO_PASSWORD=admin
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Your Twilio **Auth Token** doesn't go in `.env` — you'll enter it directly into n8n's credential store in Step 6, where it's encrypted rather than sitting in a plaintext file.

## Step 2: Start the Docker Stack (3 minutes)

```bash
docker-compose up -d
docker-compose ps
```

All three containers (`postgres_invoice_automation`, `odoo_invoice_automation`, `n8n_invoice_automation`) should show as running/healthy.

## Step 3: Set Up Odoo (5 minutes)

1. Open `http://localhost:8069`, log in with `admin` / `admin`
2. **Install the Invoicing app**: Apps → search "Invoicing" → Install
3. **Grant proper access rights** — this step is easy to skip and causes a confusing `AccessError` later: Settings → Users & Companies → Users → Administrator → Access Rights tab → set **Invoicing** to **Billing Administrator**
4. **Create 2-3 test invoices**: Invoicing → Customers → Invoices → New → fill in customer + line item → Confirm (moves it from Draft to Posted — only posted invoices get picked up)
5. **Set a real WhatsApp number on at least one test customer's contact**: Invoicing → Customers → open the contact → Mobile field → enter the number that joined your Twilio sandbox, in E.164 format with no spaces (e.g. `+923190704800`)

## Step 4: Start ngrok (2 minutes)

In a **separate terminal window that you leave running**:
```bash
ngrok http 5678
```

Copy the forwarding URL, e.g. `https://xxxx.ngrok-free.dev`. You'll need this in Step 6. If this terminal closes, the tunnel drops — restart it and update the URL in your workflow if that happens.

## Step 5: Set Up PostgreSQL Audit Database (3 minutes)

PostgreSQL's official Docker image only auto-creates one database on first start (matching `POSTGRES_USER`, so you get `odoo` for free). The `invoice_automation_logs` database used for audit logging has to be created manually:

```bash
docker exec -it postgres_invoice_automation createdb -U odoo invoice_automation_logs
```

Then build the schema inside it using the provided `init.sql`:

```bash
docker exec -i postgres_invoice_automation psql -U odoo -d invoice_automation_logs < init.sql
```

Verify it worked:
```bash
docker exec -it postgres_invoice_automation psql -U odoo -d invoice_automation_logs -c "\d invoice_deliveries"
```
You should see an 18-column table. If you instead get `relation "invoice_deliveries" does not exist`, the `createdb` step above was likely skipped or failed silently — re-run it before the `psql < init.sql` step.

## Step 6: Import Both Workflows into n8n (10 minutes)

Open `http://localhost:5678`.

**Import Workflow 2 first — it has to exist before Workflow 1 can call it:**
1. New Workflow → Menu → Import from File → select `workflows/Serve Invoice PDFs.json`
2. **Toggle it Active** (top right) — webhooks only respond when active, not just open in the editor

**Then import Workflow 1:**
1. New Workflow → Menu → Import from File → select `workflows/Invoice Automation - WhatsApp Delivery.json`
2. Open the **Format WhatsApp Number** node → update the `media_url` field's ngrok domain to match what you copied in Step 4
3. Set up credentials:
   - **Postgres**: new credential → host `postgres`, port `5432`, database `invoice_automation_logs`, user `odoo`, password `odoopass123`
   - **Twilio Basic Auth**: new Generic Credential → Basic Auth → username = your Twilio Account SID, password = your Twilio Auth Token
4. Attach the Postgres credential to both `Log Delivery to Postgres` and `Log Skip to Postgres`
5. Attach the Twilio credential to `Send via Twilio`

## Step 7: Test (5 minutes)

Run **Invoice Automation - WhatsApp Delivery** manually (Execute Workflow). Watch it flow through: authenticate → fetch invoices → loop → fetch each PDF → get contact → filter → send → log.

Check your test phone for the WhatsApp message with the PDF attached, then verify the audit trail:

```bash
docker exec -it postgres_invoice_automation psql -U odoo -d invoice_automation_logs \
  -c "SELECT invoice_number, delivery_status, customer_phone, sent_at FROM invoice_deliveries ORDER BY created_at DESC LIMIT 5;"
```

You should see rows with `delivery_status = sent` for the contact you set a real number on, and `skipped_no_phone` for any others.

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `AccessError` on `account.move` | Invoicing group not actually committed despite UI showing it set | Set it directly from Settings → Groups → Billing Administrator, not the user form dropdown |
| `session_id=null` downstream | Get Odoo Session node not returning headers | Enable "Include Response Headers and Status Code" in that node's Options |
| `403 Forbidden` fetching PDF with valid session | Wrong Odoo report name | Must be `account.report_invoice_with_payments`, not `account.report_invoice` |
| Twilio error 63015 | Recipient's sandbox join expired | Re-send `join <code>` to the sandbox number |
| Twilio "exceeded daily messages limit" | Trial account 5-message/day cap | Wait for daily reset, or upgrade the Twilio account |
| `{{$env.*}}` shows red in expression editor | Known cosmetic n8n bug | Ignore the preview; check the actual **Execute step** output instead |
| WhatsApp message never arrives despite Twilio "queued" | `media_url` unreachable | Confirm ngrok is still running and the URL in `Format WhatsApp Number` matches your current tunnel |

For deeper debugging history, see `DEBUGGING_LOG.md` — it documents every bug hit while building this, chronologically, with root causes.

---

## What's next

- `README.md` — full architecture explanation, including why this uses two workflows instead of one
- Project #2 (AI Customer Support Agent) and Project #3 (Production DevOps) are in progress as separate portfolio pieces

*Reflects the actual tested system as of the last successful end-to-end run — not a generic template.*
