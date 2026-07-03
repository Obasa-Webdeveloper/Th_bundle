-- ============================================================
-- T&H BUNDLE — Sample data for local testing
-- Run AFTER DATABASE_SCHEMA.sql
-- ============================================================

-- Sample VTU provider (points to a sandbox; replace with real credentials)
INSERT INTO api_providers (id, name, category, services, base_url, api_key, secret_key, priority, is_enabled, config)
VALUES
  (uuid_generate_v4(), 'VTpass (Primary)', 'vtu', ARRAY['data','airtime','cable_tv','electricity','education'],
   'https://sandbox.vtpass.com/api', 'sandbox_api_key', 'sandbox_secret_key', 1, true, '{"driver":"vtpass"}'),
  (uuid_generate_v4(), 'Clubkonnect (Backup)', 'vtu', ARRAY['data','airtime'],
   'https://www.nellobytesystems.com/APIclub.php', 'sandbox_user', 'sandbox_key', 2, true, '{"driver":"clubkonnect"}');

-- Sample data plans (referencing the primary provider)
DO $$
DECLARE
  provider_uuid UUID;
BEGIN
  SELECT id INTO provider_uuid FROM api_providers WHERE name = 'VTpass (Primary)' LIMIT 1;

  INSERT INTO data_plans (network, plan_name, plan_code, validity, cost_price, selling_price, provider_id) VALUES
    ('MTN', '1GB', 'mtn-1gb-30', '30 days', 320, 350, provider_uuid),
    ('MTN', '2GB', 'mtn-2gb-30', '30 days', 600, 650, provider_uuid),
    ('MTN', '5GB', 'mtn-5gb-30', '30 days', 1400, 1500, provider_uuid),
    ('AIRTEL', '1GB', 'airtel-1gb-30', '30 days', 310, 340, provider_uuid),
    ('AIRTEL', '3GB', 'airtel-3gb-30', '30 days', 850, 950, provider_uuid),
    ('GLO', '1GB', 'glo-1gb-30', '30 days', 280, 320, provider_uuid),
    ('GLO', '5GB', 'glo-5gb-30', '30 days', 1300, 1450, provider_uuid),
    ('9MOBILE', '1.5GB', '9mobile-1.5gb-30', '30 days', 400, 450, provider_uuid);
END $$;

-- Sample cable packages
DO $$
DECLARE
  provider_uuid UUID;
BEGIN
  SELECT id INTO provider_uuid FROM api_providers WHERE name = 'VTpass (Primary)' LIMIT 1;

  INSERT INTO cable_packages (provider_name, package_name, package_code, cost_price, selling_price, provider_id) VALUES
    ('DSTV', 'DStv Compact', 'dstv-compact', 10500, 10500, provider_uuid),
    ('DSTV', 'DStv Premium', 'dstv-premium', 24500, 24500, provider_uuid),
    ('GOTV', 'GOtv Max', 'gotv-max', 6200, 6200, provider_uuid),
    ('STARTIMES', 'Startimes Classic', 'startimes-classic', 3200, 3200, provider_uuid);
END $$;

-- Sample electricity discos
DO $$
DECLARE
  provider_uuid UUID;
BEGIN
  SELECT id INTO provider_uuid FROM api_providers WHERE name = 'VTpass (Primary)' LIMIT 1;

  INSERT INTO electricity_discos (disco_name, disco_code, provider_id) VALUES
    ('Ikeja Electric', 'IKEDC', provider_uuid),
    ('Eko Electric', 'EKEDC', provider_uuid),
    ('Abuja Electric', 'AEDC', provider_uuid),
    ('Port Harcourt Electric', 'PHED', provider_uuid);
END $$;

-- Sample test user (password: "Password123!")
-- bcrypt hash generated with 12 rounds — replace via your own bcrypt run if needed.
INSERT INTO users (id, full_name, email, phone, password_hash, referral_code, email_verified_at, phone_verified_at)
VALUES (
  uuid_generate_v4(), 'Test User', 'testuser@thbundle.com', '08012345678',
  '$2a$12$G8x1c2x1e2b1e3f4d5e6e.uYQyF1XyF1XyF1XyF1XyF1XyF1XyF1X', -- placeholder hash
  'TH-TEST1', NOW(), NOW()
);

-- Wallet for the test user, pre-funded for sandbox testing
DO $$
DECLARE
  test_user_id UUID;
BEGIN
  SELECT id INTO test_user_id FROM users WHERE email = 'testuser@thbundle.com';
  INSERT INTO wallets (user_id, balance) VALUES (test_user_id, 50000.00);
END $$;

-- Sample roles/permissions already seeded in schema file; sample admin account:
INSERT INTO admins (id, full_name, email, password_hash, role_id)
SELECT uuid_generate_v4(), 'Super Admin', 'admin@thbundle.com',
       '$2a$12$G8x1c2x1e2b1e3f4d5e6e.uYQyF1XyF1XyF1XyF1XyF1XyF1XyF1X', -- placeholder hash
       id FROM roles WHERE name = 'super_admin';

-- Sample coupon
INSERT INTO coupons (code, type, value, max_uses, applicable_services, expires_at)
VALUES ('WELCOME10', 'percentage', 10, 1000, ARRAY['data','airtime'], NOW() + INTERVAL '90 days');

-- Sample banner
INSERT INTO banners (image_url, link_url, is_active)
VALUES ('https://cdn.thbundle.com/banners/welcome-promo.png', 'https://thbundle.com/promo', true);
