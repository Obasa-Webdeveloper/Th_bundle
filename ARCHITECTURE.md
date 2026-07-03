# T&H BUNDLE — System Architecture

Tagline: *Fast, Reliable & Affordable Digital Services*

## 1. High-Level Overview

```
                         ┌───────────────────────┐
                         │      Flutter App       │
                         │  (Android / iOS)        │
                         └───────────┬────────────┘
                                     │ HTTPS / REST (JWT)
                         ┌───────────▼────────────┐
                         │   Nginx (reverse proxy, │
                         │   TLS termination,      │
                         │   rate limiting)         │
                         └───────────┬────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │   Node.js / Express API Layer     │
                    │  (modular: auth, wallet, vtu,     │
                    │   payments, admin, notifications) │
                    └───┬───────┬───────┬───────┬──────┘
                        │       │       │       │
             ┌──────────▼┐ ┌────▼───┐ ┌─▼─────┐ ┌▼─────────────┐
             │ PostgreSQL │ │ Redis  │ │  S3 /  │ │ Firebase FCM │
             │ (primary   │ │(queue, │ │Firebase│ │ (push notif) │
             │  DB)       │ │ cache, │ │Storage │ │              │
             │            │ │ OTP)   │ │        │ │              │
             └────────────┘ └────────┘ └────────┘ └──────────────┘

     External integrations (behind provider-abstraction layer):
     ┌────────────┬─────────────┬───────────┬───────────────────┐
     │ Paystack   │ Flutterwave │ Monnify   │ VTU Providers      │
     │            │             │           │ (VTpass, Clubkonnect,│
     │            │             │           │  Gsubz, custom…)   │
     └────────────┴─────────────┴───────────┴───────────────────┘

                    Admin Web Dashboard (React/Vue or server-rendered)
                    talks to the same API with elevated RBAC scopes.
```

## 2. Design Principles

1. **Provider abstraction, not hardcoding.** Every VTU provider and every payment gateway implements a common interface (`purchaseData()`, `purchaseAirtime()`, `payBill()`, `verifyTransaction()` / `initiatePayment()`, `verifyPayment()`). The Admin Dashboard stores provider config (base URL, API key, priority, enabled/disabled, supported services) in the DB — code never needs to change to add/remove/reorder a provider.
2. **Automatic failover.** A `ProviderManager` service picks the highest-priority *enabled* provider for a given service (e.g. "MTN data"), attempts the call, and on failure (timeout, non-2xx, provider-reported error) falls through to the next provider in priority order, logging each attempt. This is config-driven, not a code deploy.
3. **Idempotent, ledger-based wallet.** Every wallet credit/debit is a row in `wallet_transactions`; wallet `balance` is a materialized/cached value recomputed from or reconciled against the ledger, not the sole source of truth. All VTU purchases are wrapped in a DB transaction: debit wallet → call provider → on failure, auto-reverse (refund) → log everything.
4. **Idempotency keys** on all payment webhook and purchase endpoints to prevent double-charging on retries.
5. **Security by default**: HTTPS-only, JWT (short-lived access + refresh token), bcrypt password hashing, per-route input validation (Joi/Zod), parameterized queries via ORM (Sequelize/Prisma) to prevent SQL injection, helmet.js + CSP for XSS, CSRF tokens for the admin dashboard's session-based routes, express-rate-limit + Redis store, OTP for phone/email verification, optional TOTP-based 2FA.
6. **Modular monolith → microservice-ready.** Backend organized as independent modules (auth, wallet, vtu, payments, notifications, admin) each with its own routes/controllers/services, so any module can later be split into its own service without a rewrite.
7. **RBAC everywhere.** Admin users have roles; roles have permissions; every admin route checks a permission, not a hardcoded role name — new admin roles can be created without code changes.

## 3. Backend Module Map

```
backend/src/
├── config/          # env, db, redis, firebase, logger config
├── models/          # Sequelize models (see docs/DATABASE_SCHEMA.sql)
├── middleware/       # auth (JWT), rbac, validate, rateLimiter, errorHandler
├── routes/           # one router per domain
├── controllers/       # thin HTTP layer, calls services
├── services/
│   ├── providers/     # ProviderManager + adapters (VTpassAdapter, ClubkonnectAdapter…)
│   ├── payment/        # PaystackService, FlutterwaveService, MonnifyService
│   ├── wallet.service.js
│   ├── otp.service.js
│   ├── notification.service.js (FCM + in-app)
│   └── receipt.service.js (PDF generation)
├── jobs/              # cron/queue workers (reconciliation, wallet sweep, referral payout)
└── utils/
```

## 4. Request Flow: "Buy MTN Data"

1. App calls `POST /api/v1/vtu/data/purchase` with JWT, `{network, plan_id, phone, amount}`.
2. Middleware: `authenticate` → `validate(schema)` → `rateLimiter`.
3. `VtuController.purchaseData` starts a DB transaction:
   a. Lock wallet row, check `balance >= amount`.
   b. Debit wallet, insert `wallet_transactions` row (status `pending`).
   c. Insert `data_purchases` row (status `pending`).
4. Commit debit transaction (money is reserved even if provider call is slow).
5. `ProviderManager.execute('DATA', payload)`:
   - Fetch enabled providers for `DATA` + network, ordered by `priority`.
   - Try provider #1 → on error/timeout, log to `provider_logs`, try provider #2, etc.
6. On success: mark `data_purchases.status = success`, mark wallet_transaction `success`, generate receipt, push notification, respond to app.
7. On total failure (all providers down): reverse the wallet debit (credit back), mark transaction `failed/reversed`, notify user, alert admin (fraud/ops monitoring).

## 5. Deployment Topology

```
Internet → Cloudflare/DNS → Nginx (Ubuntu, TLS via Let's Encrypt)
             ├── / (static admin dashboard build)
             └── /api → Node.js app (PM2 or Docker container, N replicas)
                              │
                    Docker network: api, postgres, redis
Backups: nightly pg_dump → S3, WAL archiving for PITR (optional).
CI/CD: GitHub Actions → build & test → build Docker image → push to registry → deploy via SSH/Docker Compose or Kubernetes.
```

See `DEPLOYMENT.md` for step-by-step.

## 6. Tech Stack Summary

| Layer | Choice |
|---|---|
| Mobile | Flutter 3.x, Material 3, Riverpod, Dio, go_router |
| Backend | Node.js 20 + Express, Sequelize (Postgres) |
| DB | PostgreSQL 15 |
| Cache/Queue | Redis (OTP, rate-limit store, BullMQ jobs) |
| Storage | AWS S3 (or Firebase Storage) for KYC docs, receipts |
| Push | Firebase Cloud Messaging |
| Payments | Paystack, Flutterwave, Monnify SDK/REST |
| Admin UI | React + Vite + Tailwind (SPA) consuming same REST API |
| Infra | Docker, Docker Compose, Nginx, Ubuntu 22.04, GitHub Actions CI/CD |
| Monitoring | Winston/Pino logs → file/ELK, Sentry for errors |
