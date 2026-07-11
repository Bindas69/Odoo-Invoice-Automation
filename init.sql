-- PostgreSQL Init Script for Invoice Automation Audit Logs
--
-- IMPORTANT: PostgreSQL does not support `CREATE DATABASE IF NOT EXISTS`
-- (that's MySQL syntax) and CREATE DATABASE cannot run inside a multi-statement
-- transaction the way this file is executed. The `invoice_automation_logs` and
-- `n8n_db` databases must exist BEFORE this script runs. In this project they
-- were created manually:
--
--   docker exec -it postgres_invoice_automation createdb -U odoo invoice_automation_logs
--   docker exec -it postgres_invoice_automation createdb -U odoo n8n_db
--
-- (`odoo` — the default database — is auto-created by the official Postgres
-- image because POSTGRES_USER=odoo in docker-compose.yml.)
--
-- This script only builds the schema INSIDE invoice_automation_logs. Run it with:
--   docker exec -i postgres_invoice_automation psql -U odoo -d invoice_automation_logs < init.sql

-- Create invoice_deliveries table for WhatsApp delivery tracking
CREATE TABLE IF NOT EXISTS invoice_deliveries (
  id SERIAL PRIMARY KEY,
  invoice_id INTEGER NOT NULL,
  invoice_number VARCHAR(100) NOT NULL,
  customer_id INTEGER,
  customer_name VARCHAR(255),
  customer_phone VARCHAR(20) NOT NULL,
  delivery_channel VARCHAR(50) DEFAULT 'whatsapp', -- currently always 'whatsapp'
  delivery_status VARCHAR(50) NOT NULL, -- 'sent' | 'skipped_no_phone' (only two values the workflow currently writes; schema allows more for future retry logic)
  attempt_count INTEGER DEFAULT 1,
  max_attempts INTEGER DEFAULT 3, -- reserved for future retry logic, not yet implemented
  sent_at TIMESTAMP,
  error_message TEXT,
  error_code VARCHAR(50),
  twilio_sid VARCHAR(100), -- Twilio message SID for reference
  pdf_size INTEGER, -- Size of PDF in bytes
  response_time_ms INTEGER, -- API response time in milliseconds
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_invoice_id ON invoice_deliveries(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_number ON invoice_deliveries(invoice_number);
CREATE INDEX IF NOT EXISTS idx_customer_phone ON invoice_deliveries(customer_phone);
CREATE INDEX IF NOT EXISTS idx_delivery_status ON invoice_deliveries(delivery_status);
CREATE INDEX IF NOT EXISTS idx_sent_at ON invoice_deliveries(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_created_at ON invoice_deliveries(created_at DESC);

-- Grant permissions to odoo user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO odoo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO odoo;

-- Auto-update updated_at on any row change
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_invoice_deliveries_updated_at ON invoice_deliveries;
CREATE TRIGGER update_invoice_deliveries_updated_at
BEFORE UPDATE ON invoice_deliveries
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Success rate view (works today, since delivery_status only ever holds 'sent' / 'skipped_no_phone')
CREATE OR REPLACE VIEW invoice_delivery_success_rate AS
SELECT
  DATE(created_at) as delivery_date,
  COUNT(*) as total_attempts,
  SUM(CASE WHEN delivery_status = 'sent' THEN 1 ELSE 0 END) as successful_sends,
  SUM(CASE WHEN delivery_status = 'skipped_no_phone' THEN 1 ELSE 0 END) as skipped_no_phone,
  ROUND(
    100.0 * SUM(CASE WHEN delivery_status = 'sent' THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) as success_percentage
FROM invoice_deliveries
GROUP BY DATE(created_at)
ORDER BY delivery_date DESC;

SELECT 'invoice_deliveries schema ready.' as status;
