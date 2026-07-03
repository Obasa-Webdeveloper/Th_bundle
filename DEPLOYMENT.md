# T&H BUNDLE — Deployment Guide

## 1. Prerequisites

- Ubuntu 22.04 server (2 vCPU / 4GB RAM minimum for staging)
- Docker + Docker Compose v2
- A domain with DNS pointed at the server (`api.thbundle.com`, `admin.thbundle.com`)
- Paystack/Flutterwave/Monnify live API keys
- Firebase project (Cloud Messaging + optional Storage)

## 2. Server Setup

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-plugin certbot
sudo systemctl enable docker
sudo usermod -aG docker $USER   # log out/in after this
```

## 3. Clone & Configure

```bash
git clone https://github.com/your-org/th-bundle.git /opt/thbundle
cd /opt/thbundle/backend
cp .env.example .env
nano .env   # fill in real DB password, JWT secrets, payment keys, Firebase creds
```

Generate strong secrets:
```bash
openssl rand -hex 32   # use for JWT_ACCESS_SECRET
openssl rand -hex 32   # use for JWT_REFRESH_SECRET
```

## 4. TLS Certificates (Let's Encrypt)

```bash
sudo certbot certonly --standalone -d api.thbundle.com -d admin.thbundle.com
# certs land in /etc/letsencrypt/live/... — mounted into nginx container via docker-compose.yml
```
Set up a cron/systemd timer for `certbot renew` (Let's Encrypt certs expire every 90 days).

## 5. Bring the Stack Up

```bash
cd /opt/thbundle
docker compose up -d --build
docker compose exec api npm run migrate   # run Sequelize migrations
docker compose exec api npm run seed      # optional: load sample/reference data
```

Verify:
```bash
curl https://api.thbundle.com/api/v1/health
```

## 6. Database Backups

```bash
# Nightly cron job on the host:
0 2 * * * docker compose exec -T postgres pg_dump -U postgres thbundle | gzip > /opt/backups/thbundle-$(date +\%F).sql.gz
# Then sync /opt/backups to S3 (aws s3 sync) or another off-site location.
```
Restore: `gunzip -c backup.sql.gz | docker compose exec -T postgres psql -U postgres thbundle`.

## 7. CI/CD

See `.github/workflows/ci-cd.yml`. On every push to `main`:
1. Runs the Jest test suite against a throwaway Postgres service container.
2. Builds and pushes a Docker image to GHCR.
3. SSHes into the production host, pulls the new image, restarts the `api` container, runs migrations.

Required GitHub secrets: `PROD_HOST`, `PROD_USER`, `PROD_SSH_KEY`.

## 8. Scaling Notes

- Run multiple `api` replicas behind Nginx (`docker compose up -d --scale api=3`) — the app is stateless (JWT auth, no server-side sessions), so this is safe.
- Move Redis/Postgres to managed services (RDS, ElastiCache, or DigitalOcean Managed DB) once traffic grows past a single box.
- Put BullMQ workers (referral payouts, reconciliation jobs) in a separate container/process so they don't compete with API request handling.

## 9. Maintenance Mode

Toggle via `system_settings` table (`maintenance_mode` key) from the admin dashboard — no restart required; the API checks this on each request and returns `503` with a friendly message to the mobile app.

## 10. Monitoring

- Application logs: `backend/logs/*.log` (Winston), or ship to ELK/CloudWatch.
- Recommended: add Sentry (`SENTRY_DSN` env var) for error tracking, and Uptime Robot / Better Uptime for endpoint monitoring on `/api/v1/health`.
