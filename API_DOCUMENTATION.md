# T&H BUNDLE — API Documentation

Base URL: `https://api.thbundle.com/api/v1`
Auth: `Authorization: Bearer <JWT access token>` unless noted "Public".
All responses: `{ "success": bool, "message": string, "data": {...} }`

## Auth

| Method | Endpoint | Description | Access |
|---|---|---|---|
| POST | `/auth/register` | Register (name, email, phone, password, referral_code?) | Public |
| POST | `/auth/verify-otp` | Verify email/phone OTP | Public |
| POST | `/auth/resend-otp` | Resend OTP | Public |
| POST | `/auth/login` | Login → access + refresh token | Public |
| POST | `/auth/refresh-token` | Exchange refresh token | Public |
| POST | `/auth/forgot-password` | Send reset OTP | Public |
| POST | `/auth/reset-password` | Reset password with OTP | Public |
| POST | `/auth/logout` | Invalidate refresh token | User |
| POST | `/auth/2fa/enable` | Enable TOTP 2FA | User |
| POST | `/auth/2fa/verify` | Verify TOTP code | User |

**POST /auth/register**
```json
{ "full_name": "Jane Doe", "email": "jane@x.com", "phone": "08012345678", "password": "Str0ngP@ss", "referral_code": "TH-AB12" }
```

## Profile / KYC

| Method | Endpoint | Description |
|---|---|---|
| GET | `/users/me` | Current profile |
| PATCH | `/users/me` | Update profile |
| POST | `/users/me/avatar` | Upload avatar |
| POST | `/users/me/pin` | Set/reset transaction PIN |
| POST | `/kyc` | Submit KYC (id_type, id_number, document, selfie) |
| GET | `/kyc/status` | KYC status |

## Wallet

| Method | Endpoint | Description |
|---|---|---|
| GET | `/wallet` | Balance + virtual account details |
| POST | `/wallet/fund/initiate` | Start funding (gateway: paystack\|flutterwave\|monnify) → returns checkout URL/reference |
| POST | `/wallet/fund/verify` | Verify a funding reference |
| POST | `/wallet/virtual-account/generate` | Create dedicated virtual account (Monnify/Paystack) |
| GET | `/wallet/transactions` | Paginated ledger (`?page=&limit=&type=&from=&to=`) |
| GET | `/wallet/transactions/:id/receipt` | Download PDF receipt |

## VTU — Data & Airtime

| Method | Endpoint | Description |
|---|---|---|
| GET | `/vtu/data/plans?network=MTN` | List available data plans |
| POST | `/vtu/data/purchase` | `{network, plan_id, phone, coupon_code?}` |
| POST | `/vtu/airtime/purchase` | `{network, phone, amount, coupon_code?}` |
| POST | `/vtu/airtime/convert-to-cash` | `{network, phone, pin}` (optional feature, provider-dependent) |

## Bills

| Method | Endpoint | Description |
|---|---|---|
| GET | `/bills/cable/packages?provider=DSTV` | List cable packages |
| POST | `/bills/cable/verify-smartcard` | `{provider, smartcard_number}` |
| POST | `/bills/cable/subscribe` | `{provider, smartcard_number, package_id}` |
| GET | `/bills/electricity/discos` | List DISCOs |
| POST | `/bills/electricity/verify-meter` | `{disco, meter_number, meter_type}` |
| POST | `/bills/electricity/pay` | `{disco, meter_number, meter_type, amount}` |
| POST | `/bills/education/waec` | Purchase WAEC scratch card |
| POST | `/bills/education/neco` | Purchase NECO scratch card |
| POST | `/bills/education/jamb` | Purchase JAMB ePin `{jamb_type}` |
| POST | `/bills/education/result-checker` | Purchase result checker PIN |
| POST | `/bills/betting/fund` | `{platform, customer_id, amount}` |
| POST | `/bills/sms/bulk` | `{sender_id, message, recipients[]}` |
| POST | `/bills/recharge-print` | `{network, denomination, quantity}` |

All purchase endpoints share this response shape on success:
```json
{
  "success": true,
  "message": "Purchase successful",
  "data": {
    "transaction_id": "uuid",
    "reference": "THB-2026-000123",
    "status": "success",
    "amount": 500.00,
    "wallet_balance_after": 4230.50
  }
}
```
On provider failure after all failovers exhausted: `status: "failed"`, wallet is auto-reversed, `data.refunded: true`.

## Referrals / Coupons / Notifications

| Method | Endpoint | Description |
|---|---|---|
| GET | `/referrals` | My referral code, stats, earnings |
| GET | `/referrals/history` | List of referred users & bonus status |
| POST | `/coupons/apply` | Validate a coupon code before purchase |
| GET | `/notifications` | In-app notifications |
| PATCH | `/notifications/:id/read` | Mark as read |
| POST | `/support/ticket` | Create a support ticket |
| GET | `/support/whatsapp-link` | Returns WhatsApp deep link |

## Webhooks (server-to-server, signature-verified)

| Method | Endpoint | Description |
|---|---|---|
| POST | `/webhooks/paystack` | Paystack event (verify `x-paystack-signature`) |
| POST | `/webhooks/flutterwave` | Flutterwave event (verify `verif-hash`) |
| POST | `/webhooks/monnify` | Monnify event (verify SHA512 signature) |

## Admin API (session/JWT + RBAC permission per route)

| Method | Endpoint | Permission |
|---|---|---|
| GET | `/admin/dashboard/summary` | any admin |
| GET/POST/PATCH | `/admin/users` | `users.view` / `users.manage` |
| POST | `/admin/wallets/:userId/fund` | `wallet.manual_fund` |
| GET | `/admin/transactions` | `transactions.view` |
| GET/POST/PATCH/DELETE | `/admin/providers` | `api.manage` |
| PATCH | `/admin/pricing/:planId` | `pricing.manage` |
| PATCH | `/admin/services/:code/toggle` | `services.toggle` |
| GET/POST/DELETE | `/admin/banners` | `banners.manage` |
| POST | `/admin/notifications/broadcast` | `notifications.broadcast` |
| GET/PATCH | `/admin/referrals/settings` | `referrals.manage` |
| GET/POST/PATCH | `/admin/coupons` | `coupons.manage` |
| GET/PATCH | `/admin/complaints` | `complaints.manage` |
| GET | `/admin/audit-logs` | `audit.view` |
| GET/POST/PATCH | `/admin/admins` (accounts + roles) | `admins.manage` |
| PATCH | `/admin/system/maintenance-mode` | `system.configure` |
| POST | `/admin/system/backup` | `system.configure` |
| GET/POST | `/admin/blacklist` | `users.manage` |

## Error Codes

| HTTP | Meaning |
|---|---|
| 400 | Validation error |
| 401 | Missing/invalid token |
| 403 | Insufficient permission / KYC required |
| 404 | Resource not found |
| 409 | Duplicate (e.g. reference reuse) |
| 422 | Insufficient wallet balance |
| 429 | Rate limited |
| 503 | All providers unavailable for requested service |

## Conventions

- All list endpoints support `?page=1&limit=20` and return `meta: {page, limit, total, totalPages}`.
- All monetary amounts are decimal strings/numbers in NGN, 2dp.
- All mutating requests from the mobile app that touch wallet balance require an `Idempotency-Key` header.
