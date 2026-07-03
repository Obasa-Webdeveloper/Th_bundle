# T&H BUNDLE

**Fast, Reliable & Affordable Digital Services** — a VTU (Virtual Top-Up) platform for the Nigerian market: data, airtime, cable TV, electricity, education pins, betting wallet funding, bulk SMS, and recharge card printing, backed by a digital wallet and an admin dashboard.

> **Scope note:** This repository is a production-grade **foundation** — real architecture, schema, working backend (auth, wallet ledger, provider failover, payments), and a working Flutter skeleton (theme, navigation, key screens) — not a finished, App-Store-ready product. See "What's implemented vs. scaffolded" below before you plan a launch date.

## Repository Structure

```
th-bundle/
├── backend/            # Node.js + Express REST API
├── mobile/             # Flutter app (Android/iOS)
├── admin-dashboard/     # (to be built) React/Vue admin SPA — see docs/ARCHITECTURE.md
├── docs/                # Architecture, DB schema, API docs, deployment guide
├── deploy/              # Nginx config, certs mount point
├── docker-compose.yml
└── .github/workflows/    # CI/CD pipeline
```

## Quick Start (local development)

```bash
# 1. Backend
cd backend
cp .env.example .env        # fill in DB/JWT/payment keys
npm install
npm run migrate
npm run seed
npm run dev                  # http://localhost:4000

# 2. Mobile app
cd ../mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:4000/api/v1

# Or bring up the whole stack with Docker:
docker compose up -d --build
```

## What's Implemented vs. Scaffolded

| Area | Status |
|---|---|
| Architecture, DB schema (20+ tables), API spec | ✅ Complete design |
| Auth (register/login/OTP/JWT/refresh) | ✅ Working code |
| Wallet ledger (debit/credit/auto-reverse, DB-transaction safe) | ✅ Working code |
| VTU provider failover engine (`ProviderManager`) | ✅ Working code, one example adapter (VTpass-style) |
| Data purchase end-to-end flow | ✅ Working code (wallet debit → provider → refund-on-failure) |
| Airtime, cable TV, electricity, education, betting, SMS, recharge print | 🔶 Same pattern as data purchase — routes/controllers stubbed, need adapters + real provider credentials |
| Payment gateways (Paystack, Flutterwave) | ✅ Service classes for initiate/verify/webhook-verify. Monnify: same pattern, not yet written |
| Admin dashboard (React SPA) | 🔶 Designed (routes, RBAC permissions in schema), not scaffolded as code yet |
| Flutter UI | ✅ Theme, navigation, splash/onboarding/login/register/home/wallet/fund/buy-data screens working. Remaining screens (airtime, electricity, cable, education, betting, referral, KYC, settings, profile, notifications) follow the same pattern |
| Tests | ✅ Sample Jest integration + unit tests; needs full coverage |
| CI/CD, Docker, Nginx, deployment guide | ✅ Complete and usable |
| Push notifications (FCM) | 🔶 Dependency wired in mobile app; server-side FCM sender service not yet written |
| KYC document upload / review flow | 🔶 Schema + API routes designed, not implemented |

## Where to Look

- **`docs/ARCHITECTURE.md`** — system design, request flow, failover logic, deployment topology
- **`docs/DATABASE_SCHEMA.sql`** — full normalized Postgres schema, ready to run
- **`docs/API_DOCUMENTATION.md`** — every planned endpoint, request/response shapes
- **`docs/DEPLOYMENT.md`** — step-by-step production deployment on Ubuntu + Docker + Nginx
- **`docs/USER_MANUAL.md`** — end-user guide to the app
- **`docs/API_INTEGRATION_GUIDE.md`** — how to plug in a new VTU or payment provider without touching business logic

## Extending: Adding a New VTU Provider

1. Create `backend/src/services/providers/YourProviderAdapter.js` extending `BaseVtuAdapter`.
2. Register it in `ProviderManager.ADAPTER_REGISTRY`.
3. From the (future) admin dashboard, insert an `api_providers` row with `config.driver = 'yourprovider'`, its base URL/keys, supported `services`, and `priority`.
4. Done — no other code changes. The failover engine picks it up automatically.

## Extending: Adding a New Payment Gateway

Follow `PaystackService` / `FlutterwaveService` as templates: `initiate()`, `verify()`, `verifyWebhookSignature()`. Wire a new `/webhooks/<gateway>` route and add it to the wallet funding gateway enum.

## License

Proprietary — © T&H BUNDLE. All rights reserved.
