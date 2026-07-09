# Repository Guide

- `README.md` — architecture, setup, and design decisions
- `QUICKSTART.md` — step-by-step working setup guide
- `DEBUGGING_LOG.md` — real bugs hit while building this, chronologically
- `docker-compose.yml` — local dev environment (Postgres, Odoo, n8n)
- `init.sql` — creates the `invoice_deliveries` audit table
- `.env.example` — required environment variables
- `workflows/Invoice Automation - WhatsApp Delivery.json` — main workflow export
- `workflows/Serve Invoice PDFs.json` — stateless PDF-serving webhook export
- `LICENSE` — MIT