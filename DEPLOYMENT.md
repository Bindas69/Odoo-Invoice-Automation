# Roadmap (Not Yet Built)

Current status: runs locally via Docker Compose only.

Planned for a future iteration:
- VPS deployment (DigitalOcean or similar) with Nginx reverse proxy + SSL
- Automated PostgreSQL backups
- n8n queue mode for higher invoice volume# 🚀 Production Deployment Guide

Deploy the Odoo Invoice Automation workflow to a live server (DigitalOcean, AWS, or Heroku).

---

**Below is the Architecture understanding for Future Refrences**

## Overview: Deployment Architecture

```
Your Local Machine
    ↓ (git push)
GitHub Repository
    ↓ (docker pull)
DigitalOcean VPS / AWS EC2
    ├─ Nginx (Reverse Proxy)
    ├─ n8n (Port 5678, internal)
    ├─ Odoo (Port 8069, internal)
    └─ PostgreSQL (Port 5432, internal)
    
    ↓ (HTTPS via Let's Encrypt)
    
Internet (users access https://automation.yourdomain.com)
```

---

## Option 1: Deploy to DigitalOcean (Recommended for Beginners)

### Prerequisites
- DigitalOcean account (create at https://www.digitalocean.com)
- Domain name (e.g., automation.yourdomain.com)
- SSH key generated locally

### Step 1: Create a Droplet

1. Go to **DigitalOcean Console** → **Create** → **Droplets**
2. Choose image: **Ubuntu 24.04 LTS** (x64)
3. Choose size: **$6/month** (2GB RAM, 50GB SSD) — minimum recommended
4. Region: Choose closest to your users
5. Authentication: **SSH Key** (add your public key)
6. Click **Create Droplet**

Wait 2-3 minutes for droplet to start.

### Step 2: Connect to Your Server

```bash
# SSH into your droplet
ssh root@YOUR_DROPLET_IP

# Update system packages
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget git build-essential
```

### Step 3: Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

### Step 4: Clone Repository

```bash
# Create deployment directory
mkdir -p /root/production
cd /root/production

# Clone your GitHub repo
git clone https://github.com/yourusername/Odoo-Invoice-Automation.git
cd Odoo-Invoice-Automation
```

### Step 5: Set Up Environment Variables

```bash
# Copy .env file from your local machine or create new one
nano .env

# Add your production credentials:
# ODOO_URL=http://localhost:8069 (internal)
# TWILIO_ACCOUNT_SID=...
# TWILIO_AUTH_TOKEN=...
# etc.
```

### Step 6: Start Services with Docker Compose

```bash
# Build and start all services
docker-compose -f docker-compose.prod.yml up -d

# Check status
docker-compose ps
docker-compose logs -f n8n

# Wait for services to start (1-2 minutes)
```

### Step 7: Setup Nginx Reverse Proxy

Create `/etc/nginx/sites-available/automation`:

```nginx
server {
    listen 80;
    server_name automation.yourdomain.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name automation.yourdomain.com;

    # SSL certificates (configure below)
    ssl_certificate /etc/letsencrypt/live/automation.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/automation.yourdomain.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Reverse proxy to n8n
    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable the site:

```bash
ln -s /etc/nginx/sites-available/automation /etc/nginx/sites-enabled/
nginx -t  # Test config
systemctl restart nginx
```

### Step 8: Install SSL Certificate (Let's Encrypt)

```bash
# Install Certbot
apt install -y certbot python3-certbot-nginx

# Generate certificate
certbot certonly --standalone -d automation.yourdomain.com

# Auto-renewal
systemctl enable certbot.timer
systemctl start certbot.timer
```

### Step 9: Configure DNS

1. Go to your domain registrar (GoDaddy, Namecheap, etc.)
2. Update DNS records:
   - **Type:** A Record
   - **Host:** automation
   - **Value:** YOUR_DROPLET_IP
   - **TTL:** 3600

Wait 5-10 minutes for DNS to propagate.

### Step 10: Verify Deployment

```bash
# Test HTTPS access
curl https://automation.yourdomain.com

# Check n8n logs
docker-compose logs n8n

# Monitor resources
docker stats
```

Visit: `https://automation.yourdomain.com` in your browser.

---

## Option 2: Deploy to AWS EC2

### Prerequisites
- AWS account
- VPC and security group configured
- Elastic IP address

### Step 1: Launch EC2 Instance

1. AWS Console → **EC2** → **Launch Instances**
2. Image: **Ubuntu Server 24.04 LTS**
3. Instance type: **t3.small** (1GB RAM minimum, $0.02/hour)
4. Storage: **30GB EBS**
5. Security Group: Allow ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
6. Key pair: Create or use existing key

### Step 2: Connect and Install

```bash
# SSH into instance
ssh -i your-key.pem ubuntu@YOUR_EC2_IP

# Elevate to root
sudo su -

# Follow Docker installation steps from Option 1, Step 3
```

### Step 3-10: Repeat Steps 4-10 from Option 1

The deployment is identical after Docker is installed.

### Elastic IP (Optional but Recommended)

To prevent IP changes on reboot:

```bash
# AWS Console → Elastic IPs → Allocate → Associate with instance
```

---

## Option 3: Deploy to Heroku (Simplest, But Limited)

### Prerequisites
- Heroku account
- Heroku CLI installed

### Deploy

```bash
# Login to Heroku
heroku login

# Create app
heroku create invoice-automation

# Set environment variables
heroku config:set ODOO_URL=http://your-odoo.com
heroku config:set TWILIO_ACCOUNT_SID=...

# Deploy
git push heroku main
```

**Limitations:**
- Free tier limited to 550 hours/month
- Dyno sleeps after 30 minutes of inactivity (not ideal for scheduled workflows)
- Better for prototyping than production

---

## Monitoring in Production

### Check Service Status

```bash
# View running containers
docker-compose ps

# Check n8n logs
docker-compose logs n8n --tail=50 --follow

# Check Odoo logs
docker-compose logs odoo --tail=50

# Check PostgreSQL logs
docker-compose logs postgres --tail=50
```

### Set Up Log Aggregation (Optional)

Use **Papertrail** or **DataDog** for centralized logging:

```bash
# Install Papertrail agent
apt-get install remote-syslog

# Configure to forward logs
echo "/var/log/syslog" >> /etc/log_files.conf
```

### CPU and Memory Monitoring

```bash
# Real-time resource usage
docker stats

# Set up alerts (DigitalOcean Dashboard)
# → Monitoring → Create Alert Policy
# → Alert when CPU > 80% or Memory > 90%
```

---

## Backup Strategy

### Daily Backup to S3/DigitalOcean Spaces

Create `/root/backup.sh`:

```bash
#!/bin/bash

# Backup PostgreSQL
BACKUP_DATE=$(date +%Y-%m-%d_%H-%M-%S)
docker-compose exec -T postgres pg_dump -U odoo -d odoo_db > /backups/odoo_db_$BACKUP_DATE.sql
docker-compose exec -T postgres pg_dump -U odoo -d n8n_db > /backups/n8n_db_$BACKUP_DATE.sql

# Backup n8n workflows (JSON exports)
docker-compose exec -T n8n n8n export:workflow --all --output /backups/workflows_$BACKUP_DATE.json

# Upload to S3 (using AWS CLI)
aws s3 sync /backups/ s3://my-backup-bucket/

# Keep only last 30 days
find /backups -mtime +30 -delete

echo "Backup completed at $BACKUP_DATE"
```

Make executable and add to crontab:

```bash
chmod +x /root/backup.sh

# Run daily at 2 AM
echo "0 2 * * * /root/backup.sh" | crontab -
```

---

## Scaling for High Volume

As you grow beyond 5,000 invoices/month:

### Upgrade Droplet
```bash
# Upgrade from $6/mo to $12/mo (4GB RAM)
# DigitalOcean Console → Droplet → Resize
```

### Enable n8n Queue Mode
```bash
# Edit docker-compose.prod.yml
environment:
  - N8N_EXECUTION_MODE=queue
  - N8N_QUEUE_MODE_REDIS_HOST=redis
  
# Add Redis service
redis:
  image: redis:7-alpine
  ports:
    - "6379:6379"
```

### Load Balancing (Multi-Region)
- Set up multiple droplets in different regions
- Use DigitalOcean Load Balancer
- Sync databases with PostgreSQL replication

---

## Troubleshooting Production Issues

### Problem: n8n won't start
```bash
# Check logs
docker-compose logs n8n

# Common issues:
# - Port 5678 already in use: netstat -tlnp | grep 5678
# - Database connection failed: verify DB_* env vars
# - Out of memory: upgrade droplet

# Restart service
docker-compose restart n8n
```

### Problem: High CPU usage
```bash
# Identify problematic workflow
docker top [container_id]

# Check n8n execution queue
curl http://localhost:5678/api/v1/executions

# Disable queue if too many pending
# Or upgrade droplet
```

### Problem: SSL certificate expired
```bash
# Renew immediately
certbot renew --force-renewal

# Check expiration date
openssl x509 -in /etc/letsencrypt/live/automation.yourdomain.com/fullchain.pem -noout -dates
```

---

## Security Hardening

### Firewall Rules

```bash
# Allow SSH, HTTP, HTTPS only
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
ufw enable
```

### Update n8n Admin Password

```bash
# SSH into n8n container
docker-compose exec n8n bash

# Change password via n8n CLI
n8n user:change:password --email admin@yourdomain.com
```

### Regular Updates

```bash
# Weekly updates
apt update && apt upgrade -y

# Docker image updates
docker-compose pull
docker-compose up -d
```

---

## Performance Tuning

### Optimize n8n

```bash
# Increase worker threads
N8N_WORKERS_CONCURRENCY=10

# Increase execution timeout (in seconds)
N8N_EXECUTION_TIMEOUT=600

# Enable CPU profiling
N8N_LOG_LEVEL=debug
```

### PostgreSQL Optimization

```sql
-- Increase connections
ALTER SYSTEM SET max_connections = 200;

-- Increase shared buffers (for 4GB RAM)
ALTER SYSTEM SET shared_buffers = '1GB';

-- Increase effective cache size
ALTER SYSTEM SET effective_cache_size = '3GB';

-- Reload config
SELECT pg_reload_conf();
```

---

## Cost Breakdown (Production Setup)

| Service | Cost/Month | Notes |
|---------|-----------|-------|
| DigitalOcean Droplet | $12 | 2GB RAM, 50GB SSD |
| Domain name | $10–15 | Via any registrar |
| SSL Certificate | $0 | Let's Encrypt (free) |
| Backups | $5 | DigitalOcean Spaces |
| Monitoring | $0–50 | Datadog or free tools |
| **Total** | **$27–77** | Per month |

---

## What's Next?

✅ Production deployment complete!

1. **Monitor for 24-48 hours** → Ensure stability
2. **Test failover** → Stop container, verify auto-restart
3. **Set up monitoring dashboards** → CPU, memory, error rates
4. **Configure daily backups** → Test restore procedure
5. **Document setup** → Create runbook for your team

---

## Support

**Deployment issues?**
- 📖 DigitalOcean Docs: https://docs.digitalocean.com
- 🆘 n8n Docs: https://docs.n8n.io
- 💬 Community: https://community.n8n.io

---

**Deployment successful! 🎉**

*Last updated: June 2026*
