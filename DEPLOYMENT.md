# Roadmap (Not Yet Built)

Current status: this project runs locally via Docker Compose only. Nothing below has been deployed, tested, or verified — it's a planning document, not a guide.

Planned for a future iteration:
- VPS deployment (DigitalOcean or similar) with Nginx reverse proxy + SSL
- Automated PostgreSQL backups
- n8n queue mode for higher invoice volume
- Dedicated Odoo API user with Invoicing-only access, replacing local `admin`/`admin`

No timeline attached — this will get built out as part of a future project, once there's an actual need for production deployment (a real client, or Project #3's DevOps scope).