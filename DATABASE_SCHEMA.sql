-- ============================================================
-- T&H BUNDLE — PostgreSQL Schema
-- Run: psql -U postgres -d thbundle -f DATABASE_SCHEMA.sql
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- USERS
-- ------------------------------------------------------------
CREATE TABLE users (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name         VARCHAR(150) NOT NULL,
    email             VARCHAR(150) UNIQUE NOT NULL,
    phone             VARCHAR(20) UNIQUE NOT NULL,
    password_hash     VARCHAR(255) NOT NULL,
    referral_code     VARCHAR(20) UNIQUE NOT NULL,
    referred_by       UUID REFERENCES users(id),
    email_verified_at TIMESTAMP,
    phone_verified_at TIMESTAMP,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret  VARCHAR(255),
    is_active         BOOLEAN DEFAULT TRUE,
    is_blacklisted    BOOLEAN DEFAULT FALSE,
    pin_hash          VARCHAR(255), -- transaction PIN
    avatar_url        TEXT,
    last_login_at     TIMESTAMP,
    created_at        TIMESTAMP DEFAULT NOW(),
    updated_at        TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_phone ON users(phone);

-- ------------------------------------------------------------
-- KYC
-- ------------------------------------------------------------
CREATE TABLE kyc_verifications (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id_type        VARCHAR(30) NOT NULL, -- NIN, BVN, Driver's License, Voter's Card
    id_number      VARCHAR(50) NOT NULL,
    document_url   TEXT,
    selfie_url     TEXT,
    status         VARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected
    reviewed_by    UUID,
    rejection_reason TEXT,
    created_at     TIMESTAMP DEFAULT NOW(),
    updated_at     TIMESTAMP DEFAULT NOW()
);

-- ------------------------------------------------------------
-- OTP
-- ------------------------------------------------------------
CREATE TABLE otps (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    destination VARCHAR(150) NOT NULL, -- email or phone
    channel     VARCHAR(10) NOT NULL,  -- email, sms
    purpose     VARCHAR(30) NOT NULL,  -- verify_email, verify_phone, reset_password, 2fa
    code_hash   VARCHAR(255) NOT NULL,
    expires_at  TIMESTAMP NOT NULL,
    consumed_at TIMESTAMP,
    attempts    INT DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- ------------------------------------------------------------
-- WALLETS  (ledger-backed)
-- ------------------------------------------------------------
CREATE TABLE wallets (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance         NUMERIC(14,2) DEFAULT 0.00,
    bonus_balance   NUMERIC(14,2) DEFAULT 0.00, -- cashback / referral bonus, may have withdrawal rules
    virtual_account_number VARCHAR(20),
    virtual_account_bank   VARCHAR(100),
    virtual_account_provider VARCHAR(50), -- e.g. monnify, paystack, flutterwave
    is_locked       BOOLEAN DEFAULT FALSE, -- fraud freeze
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE wallet_transactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id       UUID NOT NULL REFERENCES wallets(id),
    reference       VARCHAR(64) UNIQUE NOT NULL, -- idempotency key
    type            VARCHAR(20) NOT NULL, -- credit, debit
    source          VARCHAR(30) NOT NULL, -- funding, purchase, refund, referral_bonus, cashback, admin_adjustment
    amount          NUMERIC(14,2) NOT NULL,
    balance_before  NUMERIC(14,2) NOT NULL,
    balance_after   NUMERIC(14,2) NOT NULL,
    status          VARCHAR(20) DEFAULT 'pending', -- pending, success, failed, reversed
    meta            JSONB,
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_wtx_wallet ON wallet_transactions(wallet_id);
CREATE INDEX idx_wtx_reference ON wallet_transactions(reference);

-- ------------------------------------------------------------
-- FUNDING (payment gateway deposits)
-- ------------------------------------------------------------
CREATE TABLE funding_transactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id),
    gateway         VARCHAR(30) NOT NULL, -- paystack, flutterwave, monnify, bank_transfer, ussd, card
    gateway_reference VARCHAR(100) UNIQUE NOT NULL,
    amount          NUMERIC(14,2) NOT NULL,
    fee             NUMERIC(14,2) DEFAULT 0,
    status          VARCHAR(20) DEFAULT 'pending', -- pending, success, failed
    webhook_payload JSONB,
    verified_at     TIMESTAMP,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- ------------------------------------------------------------
-- API PROVIDERS (VTU + payment) — admin configurable
-- ------------------------------------------------------------
CREATE TABLE api_providers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(100) NOT NULL,
    category        VARCHAR(30) NOT NULL, -- vtu, payment
    services        TEXT[] NOT NULL,      -- ['data','airtime','cable_tv','electricity','education','betting','sms']
    base_url        TEXT NOT NULL,
    api_key         TEXT,
    secret_key      TEXT,
    priority        INT DEFAULT 1,        -- lower = tried first
    is_enabled      BOOLEAN DEFAULT TRUE,
    config          JSONB, -- provider-specific extra fields
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE provider_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id     UUID REFERENCES api_providers(id),
    request_type    VARCHAR(30),
    request_payload JSONB,
    response_payload JSONB,
    status_code     INT,
    success         BOOLEAN,
    duration_ms     INT,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- ------------------------------------------------------------
-- SERVICE CATALOG (networks, plans, cable packages, pricing)
-- ------------------------------------------------------------
CREATE TABLE service_categories (
    id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code     VARCHAR(30) UNIQUE NOT NULL, -- data, airtime, cable_tv, electricity, education, betting, sms, recharge_print
    name     VARCHAR(100) NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE
);

CREATE TABLE data_plans (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    network       VARCHAR(20) NOT NULL, -- MTN, AIRTEL, GLO, 9MOBILE
    plan_name     VARCHAR(100) NOT NULL,
    plan_code     VARCHAR(50) NOT NULL, -- provider's plan code
    validity      VARCHAR(30),
    cost_price    NUMERIC(10,2) NOT NULL,   -- what we pay provider
    selling_price NUMERIC(10,2) NOT NULL,   -- what user pays (margin configurable)
    provider_id   UUID REFERENCES api_providers(id),
    is_enabled    BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP DEFAULT NOW()
);

CREATE TABLE cable_packages (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_name VARCHAR(20) NOT NULL, -- DSTV, GOTV, STARTIMES
    package_name  VARCHAR(100) NOT NULL,
    package_code  VARCHAR(50) NOT NULL,
    cost_price    NUMERIC(10,2) NOT NULL,
    selling_price NUMERIC(10,2) NOT NULL,
    provider_id   UUID REFERENCES api_providers(id),
    is_enabled    BOOLEAN DEFAULT TRUE
);

CREATE TABLE electricity_discos (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    disco_name    VARCHAR(50) NOT NULL, -- IKEDC, EKEDC, AEDC, etc.
    disco_code    VARCHAR(30) NOT NULL,
    provider_id   UUID REFERENCES api_providers(id),
    is_enabled    BOOLEAN DEFAULT TRUE
);

-- ------------------------------------------------------------
-- PURCHASE TABLES (per-service, normalized but keep a unifying view)
-- ------------------------------------------------------------
CREATE TABLE data_purchases (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id),
    wallet_tx_id    UUID REFERENCES wallet_transactions(id),
    network         VARCHAR(20) NOT NULL,
    plan_id         UUID REFERENCES data_plans(id),
    phone           VARCHAR(20) NOT NULL,
    amount          NUMERIC(10,2) NOT NULL,
    provider_id     UUID REFERENCES api_providers(id),
    provider_reference VARCHAR(100),
    status          VARCHAR(20) DEFAULT 'pending', -- pending, success, failed, reversed
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE airtime_purchases (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id),
    wallet_tx_id    UUID REFERENCES wallet_transactions(id),
    network         VARCHAR(20) NOT NULL,
    phone           VARCHAR(20) NOT NULL,
    amount          NUMERIC(10,2) NOT NULL,
    provider_id     UUID REFERENCES api_providers(id),
    provider_reference VARCHAR(100),
    status          VARCHAR(20) DEFAULT 'pending',
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE bills (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id),
    wallet_tx_id    UUID REFERENCES wallet_transactions(id),
    bill_type       VARCHAR(30) NOT NULL, -- cable_tv, electricity, education, betting, sms, recharge_print
    provider_id     UUID REFERENCES api_providers(id),
    reference_input JSONB NOT NULL, -- smartcard number, meter number, exam type, etc.
    amount          NUMERIC(10,2) NOT NULL,
    provider_reference VARCHAR(100),
    token_or_pin    TEXT, -- electricity token, WAEC pin, JAMB epin, etc.
    status          VARCHAR(20) DEFAULT 'pending',
    created_at      TIMESTAMP DEFAULT NOW()
);

-- Unified transaction view for history/receipts
CREATE VIEW v_all_transactions AS
    SELECT id, user_id, 'data' AS category, network AS label, amount, status, created_at FROM data_purchases
    UNION ALL
    SELECT id, user_id, 'airtime', network, amount, status, created_at FROM airtime_purchases
    UNION ALL
    SELECT id, user_id, bill_type, bill_type, amount, status, created_at FROM bills
    UNION ALL
    SELECT id, user_id, 'funding', gateway, amount, status, created_at FROM funding_transactions;

-- ------------------------------------------------------------
-- REFERRALS
-- ------------------------------------------------------------
CREATE TABLE referrals (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_id    UUID NOT NULL REFERENCES users(id),
    referee_id     UUID NOT NULL REFERENCES users(id),
    bonus_amount   NUMERIC(10,2) DEFAULT 0,
    status         VARCHAR(20) DEFAULT 'pending', -- pending, credited
    created_at     TIMESTAMP DEFAULT NOW()
);

-- ------------------------------------------------------------
-- COUPONS / PROMO CODES
-- ------------------------------------------------------------
CREATE TABLE coupons (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code            VARCHAR(30) UNIQUE NOT NULL,
    type            VARCHAR(20) NOT NULL, -- fixed, percentage
    value           NUMERIC(10,2) NOT NULL,
    max_uses        INT,
    used_count      INT DEFAULT 0,
    applicable_services TEXT[],
    expires_at      TIMESTAMP,
    is_enabled      BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE coupon_redemptions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    coupon_id   UUID NOT NULL REFERENCES coupons(id),
    user_id     UUID NOT NULL REFERENCES users(id),
    redeemed_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(coupon_id, user_id)
);

-- ------------------------------------------------------------
-- NOTIFICATIONS
-- ------------------------------------------------------------
CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE, -- NULL = broadcast
    title       VARCHAR(150) NOT NULL,
    body        TEXT NOT NULL,
    type        VARCHAR(30) DEFAULT 'general', -- transaction, promo, system
    is_read     BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE banners (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    image_url   TEXT NOT NULL,
    link_url    TEXT,
    is_active   BOOLEAN DEFAULT TRUE,
    starts_at   TIMESTAMP,
    ends_at     TIMESTAMP,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- ------------------------------------------------------------
-- ADMIN / RBAC
-- ------------------------------------------------------------
CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(50) UNIQUE NOT NULL, -- super_admin, admin, support, finance
    description TEXT
);

CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code        VARCHAR(60) UNIQUE NOT NULL, -- e.g. wallet.manual_fund, users.view, api.manage
    description TEXT
);

CREATE TABLE role_permissions (
    role_id       UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE admins (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name     VARCHAR(150) NOT NULL,
    email         VARCHAR(150) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id       UUID REFERENCES roles(id),
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(255),
    is_active     BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP,
    created_at    TIMESTAMP DEFAULT NOW()
);

CREATE TABLE audit_logs (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_type  VARCHAR(10) NOT NULL, -- admin, user, system
    actor_id    UUID,
    action      VARCHAR(100) NOT NULL, -- e.g. 'wallet.manual_fund', 'provider.update'
    target_type VARCHAR(50),
    target_id   UUID,
    ip_address  VARCHAR(45),
    meta        JSONB,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE complaints (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id),
    subject     VARCHAR(150) NOT NULL,
    message     TEXT NOT NULL,
    status      VARCHAR(20) DEFAULT 'open', -- open, in_progress, resolved
    assigned_to UUID REFERENCES admins(id),
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE blacklist (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type        VARCHAR(20) NOT NULL, -- phone, email, device_id, bvn
    value       VARCHAR(150) NOT NULL,
    reason      TEXT,
    created_by  UUID REFERENCES admins(id),
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE system_settings (
    key         VARCHAR(100) PRIMARY KEY,
    value       JSONB NOT NULL,
    updated_by  UUID REFERENCES admins(id),
    updated_at  TIMESTAMP DEFAULT NOW()
);
-- e.g. rows: 'maintenance_mode' -> {"enabled": false}, 'default_margin' -> {"data": 5, "airtime": 2}

-- ------------------------------------------------------------
-- Seed baseline roles & permissions
-- ------------------------------------------------------------
INSERT INTO roles (name, description) VALUES
 ('super_admin','Full system access'),
 ('admin','General admin access'),
 ('finance','Wallet & transaction management'),
 ('support','Complaints & user support');

INSERT INTO permissions (code, description) VALUES
 ('users.view','View users'),
 ('users.manage','Suspend/blacklist users'),
 ('wallet.view','View wallets'),
 ('wallet.manual_fund','Manually fund a wallet'),
 ('transactions.view','View all transactions'),
 ('api.manage','Add/edit/remove API providers'),
 ('pricing.manage','Edit pricing & margins'),
 ('services.toggle','Enable/disable services'),
 ('banners.manage','Manage banners'),
 ('notifications.broadcast','Send broadcast notifications'),
 ('referrals.manage','Manage referral settings'),
 ('coupons.manage','Manage coupons'),
 ('complaints.manage','Manage complaints'),
 ('audit.view','View audit logs'),
 ('admins.manage','Create/edit admin accounts & roles'),
 ('system.configure','Maintenance mode, backups, system settings');
