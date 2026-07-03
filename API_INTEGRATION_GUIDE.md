# T&H BUNDLE — API / Provider Integration Guide

This guide covers how to plug in new **VTU providers** (data/airtime/bills suppliers) and **payment gateways** without modifying business logic — the entire point of the provider-abstraction architecture.

## 1. Adding a New VTU Provider

### Step 1 — Write an adapter
Create `backend/src/services/providers/<Name>Adapter.js`, extending `BaseVtuAdapter`:

```js
const BaseVtuAdapter = require('./BaseVtuAdapter');

class ClubkonnectAdapter extends BaseVtuAdapter {
  async purchaseData({ network, planCode, phone, amount, reference }) {
    // Call the provider's real API here using this.provider.baseUrl / apiKey / secretKey.
    // Map their response to { success, providerReference, raw }.
  }
  async purchaseAirtime({ network, phone, amount, reference }) { /* ... */ }
  // Implement whichever methods this provider supports.
}

module.exports = ClubkonnectAdapter;
```

Only implement the methods this provider actually supports — `ProviderManager` only calls the method needed for the requested service.

### Step 2 — Register the adapter
In `backend/src/services/providers/ProviderManager.js`:
```js
const ClubkonnectAdapter = require('./ClubkonnectAdapter');
const ADAPTER_REGISTRY = {
  vtpass: VtpassAdapter,
  clubkonnect: ClubkonnectAdapter, // add this line
};
```
This is the **only** code change required per new provider.

### Step 3 — Configure it from the Admin Dashboard (or directly in DB for now)
Insert a row into `api_providers`:

```sql
INSERT INTO api_providers (name, category, services, base_url, api_key, secret_key, priority, is_enabled, config)
VALUES (
  'Clubkonnect', 'vtu', ARRAY['data','airtime','cable_tv'],
  'https://www.nellobytesystems.com/APIclub.php', 'your_user_id', 'your_api_key',
  2, true, '{"driver":"clubkonnect"}'
);
```

- `priority` controls failover order (lower = tried first).
- `services` controls which service categories this provider is eligible for.
- Setting `is_enabled = false` instantly removes it from rotation — no deploy needed.
- To reorder failover, just update `priority` values.

### Step 4 — Failover behavior
`ProviderManager.execute(service, method, payload)` tries providers for that service in priority order. If a provider throws (network error, timeout, non-2xx) or returns `{ success: false }`, it's logged to `provider_logs` and the next provider is tried automatically. If all fail, the caller (e.g. `vtu.controller.js`) auto-reverses the wallet debit.

## 2. Adding a New Payment Gateway

### Step 1 — Write a service class
Follow `PaystackService` / `FlutterwaveService` as templates. Implement at minimum:
- `initiate({ email, amount, reference, callbackUrl })` → returns a checkout URL/reference
- `verify(reference)` → returns gateway transaction status
- `verifyWebhookSignature(rawBody, signatureHeader)` → validates authenticity of incoming webhooks

### Step 2 — Wire the webhook route
Add a `POST /webhooks/<gateway>` route that:
1. Verifies the signature.
2. Looks up the `funding_transactions` row by `gateway_reference`.
3. On a successful/confirmed event, credits the user's wallet via `WalletService.credit(...)` and marks the funding row `success`. Use the gateway's transaction reference as the wallet transaction's idempotency key so a retried webhook can never double-credit.

### Step 3 — Add to the funding gateway enum
Update `fundWalletSchema` in `validationSchemas.js` and the `wallet_transactions.source`/`funding_transactions.gateway` values.

### Step 4 — Automatic payment verification
In addition to webhooks (push), the `/wallet/fund/verify` endpoint lets the app actively poll/verify a reference (pull) — useful as a fallback if a webhook is delayed or missed. Both paths converge on the same `WalletService.credit()` call, guarded by the same idempotency key, so it's safe to call both.

## 3. Pricing & Margin Configuration

`data_plans`, `cable_packages`, etc. store both `cost_price` (what we pay the provider) and `selling_price` (what the user pays). The admin dashboard's Pricing Management screen edits `selling_price` per plan, or applies a global margin percentage (stored in `system_settings.default_margin`) that a scheduled job can use to recompute `selling_price = cost_price * (1 + margin)` across all plans for a given provider.

## 4. Testing a New Provider Safely

1. Set `is_enabled = false` initially and test the adapter directly via a script or Postman against the provider's sandbox/staging credentials.
2. Set `priority` higher than existing providers (e.g. 99) and `is_enabled = true` to add it to the rotation as a low-priority fallback first.
3. Monitor `provider_logs` for real traffic before promoting it to `priority = 1`.
