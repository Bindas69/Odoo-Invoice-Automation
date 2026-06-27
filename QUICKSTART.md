# Quick Start Guide: Odoo Invoice Automation

Get your invoice automation workflow running in **15 minutes**.

---

## ✅ Pre-Flight Checklist

Before starting, verify you have:

- [ ] **Odoo 17** running locally or on a server (accessible via HTTP)
- [ ] **n8n v2.8+** installed (cloud or self-hosted)
- [ ] **PostgreSQL 16** running (for audit logs)
- [ ] **Twilio account** with WhatsApp API enabled
- [ ] A **WhatsApp-enabled phone** for testing
- [ ] This repository cloned to your machine

---

## 📋 Step-by-Step Setup

### Step 1: Clone the Repository (2 minutes)

```bash
git clone https://github.com/yourusername/Odoo-Invoice-Automation.git
cd Odoo-Invoice-Automation
```

### Step 2: Configure Environment Variables (3 minutes)

```bash
# Copy the example file
cp .env.example .env

# Edit with your actual credentials
nano .env  # or use your favorite editor
```

**Required fields to fill in:**

```env
# Test these URLs first
ODOO_URL=http://localhost:8069
N8N_URL=http://localhost:5678

# Get from your Odoo admin account
ODOO_USERNAME=admin
ODOO_PASSWORD=your_password

# Get from Twilio Console (https://www.twilio.com/console)
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_WHATSAPP_FROM=whatsapp:+1234567890
```

### Step 3: Test Odoo Connection (2 minutes)

Verify Odoo is accessible:

```bash
# Test Odoo API endpoint
curl -X POST http://localhost:8069/jsonrpc \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "call",
    "params": {
      "service": "common",
      "method": "version"
    }
  }'

# Should return: {"jsonrpc":"2.0","result":{"server_version":"17.0",...}}
```

If you get a connection error, Odoo is not running. Start it:

```bash
# From your Odoo directory
./odoo-bin -c ~/.odoorc --http-port=8069
```

### Step 4: Set Up Twilio WhatsApp (3 minutes)

1. Go to [Twilio Console](https://www.twilio.com/console)
2. Navigate to **Messaging** → **Send a WhatsApp message**
3. Create a WhatsApp sender (get your Twilio WhatsApp number)
4. Get your Account SID and Auth Token from the dashboard
5. Enable WhatsApp sandbox and add your phone number for testing

**Test Twilio connection:**

```bash
# Install twilio-cli if not already installed
npm install -g twilio-cli

# Test send message
twilio api:messages:create \
  --account-sid=$TWILIO_ACCOUNT_SID \
  --auth-token=$TWILIO_AUTH_TOKEN \
  --from='whatsapp:+1234567890' \
  --to='whatsapp:+your_phone_number' \
  --body='Test message from Twilio'
```

You should receive a WhatsApp message on your phone within 5 seconds.

### Step 5: Create PostgreSQL Database for Audit Logs (2 minutes)

```bash
# Create database and table
psql -U odoo -d invoice_automation_logs << 'EOF'

CREATE TABLE IF NOT EXISTS invoice_deliveries (
  id SERIAL PRIMARY KEY,
  invoice_id INTEGER,
  invoice_number VARCHAR(50),
  customer_phone VARCHAR(20),
  delivery_status VARCHAR(20),
  sent_at TIMESTAMP,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_invoice_id ON invoice_deliveries(invoice_id);
CREATE INDEX idx_sent_at ON invoice_deliveries(sent_at);

EOF
```

Verify table creation:

```bash
psql -U odoo -d invoice_automation_logs -c "\dt"
# Should show: invoice_deliveries table
```

### Step 6: Import Workflow into n8n (3 minutes)

#### Option A: Web UI Import (Recommended)

1. Open n8n: `http://localhost:5678`
2. Click **+ New Workflow**
3. Click **Menu** (top right) → **Import Workflow**
4. Upload file: `workflows/odoo-invoice-automation.json`
5. Click **Import**

#### Option B: API Import

```bash
# Get your n8n API key from Settings → API Keys

curl -X POST http://localhost:5678/api/v1/workflows \
  -H "Authorization: Bearer YOUR_N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d @workflows/odoo-invoice-automation.json
```

### Step 7: Configure Credentials in n8n (3 minutes)

In the n8n workflow editor:

1. **Click Node 1 (Schedule Trigger)**
   - No credentials needed; keep default settings

2. **Click Node 2 (HTTP Request - Odoo API)**
   - Click **Authentication** dropdown
   - Select **Create New** → **Generic Credential Type**
   - Set Type: **Basic Auth**
   - User: `admin`
   - Password: (your Odoo admin password)
   - Save

3. **Click Node 6 (Twilio WhatsApp)**
   - Click **Authentication** dropdown
   - Select **Create New** → **Twilio**
   - Account SID: (from .env)
   - Auth Token: (from .env)
   - Save

### Step 8: Test the Workflow (3 minutes)

1. **Create a test invoice in Odoo:**
   - Go to Odoo: `http://localhost:8069`
   - Navigate to **Sales** → **Invoices**
   - Click **Create**
   - Fill in: Customer, Amount, Due Date
   - Click **Confirm**

2. **Manually trigger the workflow in n8n:**
   - In n8n editor, click **Test Workflow**
   - Watch the execution logs for each node
   - Check if WhatsApp message arrives on your phone

3. **Verify in audit log:**
   ```bash
   psql -U odoo -d invoice_automation_logs << EOF
   SELECT * FROM invoice_deliveries ORDER BY created_at DESC LIMIT 1;
   EOF
   ```

**Expected output:**
```
 id | invoice_id | invoice_number | customer_phone | delivery_status | sent_at
----+------------+----------------+----------------+-----------------+-----
  1 |         42 | INV/2026/0001  | +1234567890    | sent            | [timestamp]
```

---

## 🚀 Deploy to Production

Once testing is successful:

```bash
# Option 1: Keep n8n running in terminal (development)
npm run start

# Option 2: Run as background service
npm install -g pm2
pm2 start n8n --name "invoice-automation"
pm2 save
pm2 startup

# Option 3: Docker Compose (recommended)
docker-compose -f docker-compose.yml up -d
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for production deployment on DigitalOcean/AWS.

---

## 🧪 Workflow Execution Flow

Here's what happens every 5 minutes:

```
1. Schedule Trigger fires (every 5 min)
   ↓
2. HTTP Request queries Odoo: "Give me all invoices from last 24 hours"
   ↓
3. Odoo returns: [invoice1, invoice2, invoice3, ...]
   ↓
4. Loop node processes EACH invoice in parallel
   ↓
5. For EACH invoice:
   a. Generate PDF from Odoo
   b. Fetch customer WhatsApp number
   c. Send WhatsApp via Twilio
   d. Log result to PostgreSQL
   ↓
6. If error: Retry up to 3 times
   ↓
7. If still failed: Send email alert to admin
```

---

## 📊 Monitoring

### View Workflow Executions

n8n dashboard: `http://localhost:5678` → Click workflow → **Executions**

Look for:
- ✅ **Green checkmarks** = successful runs
- ⚠️ **Yellow flags** = partial success
- ❌ **Red X** = failed runs (click to see error details)

### View Audit Logs

```bash
# Last 10 deliveries
psql -U odoo -d invoice_automation_logs -c \
  "SELECT invoice_number, delivery_status, sent_at FROM invoice_deliveries ORDER BY sent_at DESC LIMIT 10;"

# Check for failed deliveries
psql -U odoo -d invoice_automation_logs -c \
  "SELECT * FROM invoice_deliveries WHERE delivery_status = 'failed';"
```

### Enable Debug Logging

```bash
# Add to .env
N8N_LOG_LEVEL=debug

# Restart n8n
pkill n8n
n8n start
```

---

## 🐛 Troubleshooting

### Problem: "Cannot reach Odoo"
**Solution:**
```bash
# Verify Odoo is running
curl http://localhost:8069/web/login

# If not running, start it:
cd ~/odoo-17
source venv/bin/activate
./odoo-bin -c ~/.odoorc --http-port=8069
```

### Problem: "Twilio auth failed"
**Solution:**
1. Go to [Twilio Console](https://www.twilio.com/console)
2. Verify Account SID and Auth Token are correct
3. Copy-paste them into `.env` (no typos!)
4. Verify WhatsApp is enabled in Messaging settings

### Problem: "WhatsApp message not delivered"
**Solution:**
1. Verify phone number is in `whatsapp:+1234567890` format (with country code)
2. Ensure phone is added to Twilio WhatsApp sandbox
3. Check customer's Odoo contact has a valid phone number
4. Verify Twilio account has credits (if not using free trial)

### Problem: "PDF generation failed"
**Solution:**
1. Verify **Invoicing** or **Accounting** module is installed in Odoo
2. Check Odoo logs: `~/.local/share/odoo/logs/`
3. Verify invoice is in "Posted" state (not Draft)

### Problem: "n8n workflow not triggering"
**Solution:**
1. Verify schedule trigger is **enabled** (click toggle)
2. Check n8n execution logs for error messages
3. Test manually: Click **Test Workflow** button
4. Restart n8n service:
   ```bash
   pkill n8n
   n8n start
   ```

---

## 📞 Get Help

**Need support?**
- 📖 Read [README.md](./README.md) for full documentation
- 🆘 Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- 💬 Ask in [n8n Community Forum](https://community.n8n.io)
- 📧 Email: taha@yourdomain.com

---

## ✨ Next Steps

✅ **You just completed the setup!** What's next?

1. **Monitor for 24 hours** — Ensure workflow runs reliably
2. **Create 5 test invoices** — Verify WhatsApp delivery works consistently
3. **Update LinkedIn** — Post about your automation success!
4. **Scale to production** — See [DEPLOYMENT.md](./DEPLOYMENT.md)
5. **Build Project #2** — AI Customer Support Bot (see main README)

---

**Happy automating! 🚀**

*Last updated: June 2026*
