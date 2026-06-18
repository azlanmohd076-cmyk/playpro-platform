-- ============================================================
-- PlayPro Model 6: Critical Infrastructure DDL
-- Purpose: Source-of-truth tables for Infrastructure Standard pivot
-- Scope: NEW tables only; no frontend changes; no destructive changes.
-- Date: 2026-06-18
-- ============================================================

-- Required extension used by existing PlayPro migrations.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1) ENUMS
-- ============================================================

DO $$ BEGIN
  CREATE TYPE organization_type AS ENUM (
    'club',
    'academy',
    'league_organizer',
    'sponsor',
    'scout_agency',
    'school',
    'vendor',
    'playpro_internal'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE organization_status AS ENUM (
    'draft',
    'active',
    'suspended',
    'archived'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE passport_status AS ENUM (
    'draft',
    'pending_payment',
    'active',
    'expired',
    'suspended',
    'revoked'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE wallet_status AS ENUM (
    'active',
    'frozen',
    'closed'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE wallet_transaction_type AS ENUM (
    'assessment_fee',
    'assessor_commission',
    'playpro_net_revenue',
    'passport_fee',
    'verification_fee',
    'payout',
    'refund',
    'adjustment'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE wallet_transaction_status AS ENUM (
    'pending',
    'posted',
    'void',
    'refunded'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE verification_status AS ENUM (
    'draft',
    'pending_review',
    'verified',
    'expired',
    'suspended',
    'rejected'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 2) ORGANIZATIONS
-- Parent entity for clubs, academies, league organizers, sponsors,
-- scout agencies, schools, and future B2B customers.
-- Existing clubs/leagues remain untouched; this table links to them.
-- ============================================================

CREATE TABLE IF NOT EXISTS organizations (
  id                    UUID                 PRIMARY KEY DEFAULT uuid_generate_v4(),

  name                  TEXT                 NOT NULL,
  slug                  TEXT                 NOT NULL UNIQUE,
  type                  organization_type    NOT NULL,
  status                organization_status  NOT NULL DEFAULT 'draft',

  -- Optional bridge to existing legacy/domain tables.
  linked_club_id         UUID                 REFERENCES clubs(id) ON DELETE SET NULL,
  linked_league_id       UUID                 REFERENCES leagues(id) ON DELETE SET NULL,

  owner_profile_id       UUID                 REFERENCES profiles(id) ON DELETE SET NULL,
  admin_profile_id       UUID                 REFERENCES profiles(id) ON DELETE SET NULL,

  registration_no        TEXT,
  email                  TEXT,
  phone                  TEXT,
  website_url            TEXT,
  logo_url               TEXT,

  address_line1          TEXT,
  address_line2          TEXT,
  city                   TEXT,
  state                  TEXT,
  country                TEXT                 NOT NULL DEFAULT 'Malaysia',
  postcode               TEXT,

  metadata               JSONB                NOT NULL DEFAULT '{}'::jsonb,

  created_by             UUID                 REFERENCES profiles(id) ON DELETE SET NULL,
  created_at             TIMESTAMPTZ          NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ          NOT NULL DEFAULT NOW(),

  CONSTRAINT organizations_one_legacy_link_chk
    CHECK (
      linked_club_id IS NULL
      OR linked_league_id IS NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_organizations_type ON organizations(type);
CREATE INDEX IF NOT EXISTS idx_organizations_status ON organizations(status);
CREATE INDEX IF NOT EXISTS idx_organizations_owner_profile ON organizations(owner_profile_id);
CREATE INDEX IF NOT EXISTS idx_organizations_linked_club ON organizations(linked_club_id);
CREATE INDEX IF NOT EXISTS idx_organizations_linked_league ON organizations(linked_league_id);

-- ============================================================
-- 3) PLAYER PASSPORTS
-- Football Passport as a seasonal identity entitlement.
-- Lifetime player data stays on players + related history tables.
-- This table controls active season eligibility and RM50/season logic.
-- ============================================================

CREATE TABLE IF NOT EXISTS player_passports (
  id                    UUID             PRIMARY KEY DEFAULT uuid_generate_v4(),

  player_id             UUID             NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  season_id             UUID             REFERENCES seasons(id) ON DELETE SET NULL,
  league_id             UUID             REFERENCES leagues(id) ON DELETE SET NULL,

  passport_number       TEXT             NOT NULL UNIQUE,
  status                passport_status  NOT NULL DEFAULT 'pending_payment',
  status_aktif          BOOLEAN          NOT NULL DEFAULT false,

  issued_at             TIMESTAMPTZ,
  tarikh_mula           DATE,
  tarikh_tamat          DATE             NOT NULL,

  fee_amount            NUMERIC(12,2)    NOT NULL DEFAULT 50.00,
  currency              TEXT             NOT NULL DEFAULT 'MYR',
  payment_reference     TEXT,
  paid_at               TIMESTAMPTZ,

  verified_by           UUID             REFERENCES profiles(id) ON DELETE SET NULL,
  verified_at           TIMESTAMPTZ,

  suspension_reason     TEXT,
  revoked_reason        TEXT,
  notes                 TEXT,
  metadata              JSONB            NOT NULL DEFAULT '{}'::jsonb,

  created_by            UUID             REFERENCES profiles(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ      NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ      NOT NULL DEFAULT NOW(),

  CONSTRAINT player_passports_dates_chk
    CHECK (tarikh_tamat >= COALESCE(tarikh_mula, tarikh_tamat)),

  CONSTRAINT player_passports_active_status_chk
    CHECK (
      (status_aktif = true AND status = 'active')
      OR (status_aktif = false)
    ),

  CONSTRAINT player_passports_fee_chk
    CHECK (fee_amount >= 0),

  -- One passport entitlement per player per season.
  UNIQUE (player_id, season_id)
);

CREATE INDEX IF NOT EXISTS idx_player_passports_player ON player_passports(player_id);
CREATE INDEX IF NOT EXISTS idx_player_passports_season ON player_passports(season_id);
CREATE INDEX IF NOT EXISTS idx_player_passports_league ON player_passports(league_id);
CREATE INDEX IF NOT EXISTS idx_player_passports_status ON player_passports(status);
CREATE INDEX IF NOT EXISTS idx_player_passports_active_expiry ON player_passports(status_aktif, tarikh_tamat);

-- ============================================================
-- 4) AGENT WALLETS
-- Wallet for certified assessors, agents, scout agencies, or internal
-- PlayPro revenue buckets. This is the financial ledger anchor.
-- ============================================================

CREATE TABLE IF NOT EXISTS agent_wallets (
  id                    UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),

  profile_id             UUID           REFERENCES profiles(id) ON DELETE SET NULL,
  organization_id        UUID           REFERENCES organizations(id) ON DELETE SET NULL,

  wallet_code            TEXT           NOT NULL UNIQUE,
  status                 wallet_status  NOT NULL DEFAULT 'active',
  currency               TEXT           NOT NULL DEFAULT 'MYR',

  available_balance      NUMERIC(14,2)  NOT NULL DEFAULT 0.00,
  pending_balance        NUMERIC(14,2)  NOT NULL DEFAULT 0.00,
  lifetime_earned        NUMERIC(14,2)  NOT NULL DEFAULT 0.00,
  lifetime_paid_out      NUMERIC(14,2)  NOT NULL DEFAULT 0.00,

  payout_bank_name       TEXT,
  payout_account_name    TEXT,
  payout_account_last4   TEXT,

  metadata               JSONB          NOT NULL DEFAULT '{}'::jsonb,

  created_by             UUID           REFERENCES profiles(id) ON DELETE SET NULL,
  created_at             TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

  CONSTRAINT agent_wallet_owner_chk
    CHECK (profile_id IS NOT NULL OR organization_id IS NOT NULL),

  CONSTRAINT agent_wallet_balances_chk
    CHECK (
      available_balance >= 0
      AND pending_balance >= 0
      AND lifetime_earned >= 0
      AND lifetime_paid_out >= 0
    )
);

CREATE INDEX IF NOT EXISTS idx_agent_wallets_profile ON agent_wallets(profile_id);
CREATE INDEX IF NOT EXISTS idx_agent_wallets_organization ON agent_wallets(organization_id);
CREATE INDEX IF NOT EXISTS idx_agent_wallets_status ON agent_wallets(status);

-- ============================================================
-- 5) WALLET TRANSACTIONS
-- Immutable-style ledger rows. Use reversal/refund rows instead of
-- updating historical posted transactions.
-- Supports RM150 assessment flow and PlayPro net revenue tracking.
-- ============================================================

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id                         UUID                       PRIMARY KEY DEFAULT uuid_generate_v4(),

  wallet_id                   UUID                       NOT NULL REFERENCES agent_wallets(id) ON DELETE CASCADE,
  type                        wallet_transaction_type    NOT NULL,
  status                      wallet_transaction_status  NOT NULL DEFAULT 'pending',

  amount                      NUMERIC(14,2)              NOT NULL,
  currency                    TEXT                       NOT NULL DEFAULT 'MYR',

  -- Model 6 economics. Example assessment: gross RM150,
  -- PlayPro net target RM125, remaining amount can be commission/cost.
  gross_amount                NUMERIC(14,2),
  playpro_net_amount          NUMERIC(14,2),
  commission_amount           NUMERIC(14,2),

  player_id                   UUID                       REFERENCES players(id) ON DELETE SET NULL,
  organization_id             UUID                       REFERENCES organizations(id) ON DELETE SET NULL,
  related_passport_id          UUID                       REFERENCES player_passports(id) ON DELETE SET NULL,

  -- Link to existing assessment tables when the transaction comes from
  -- coach/scout assessment activity.
  player_assessment_id         UUID                       REFERENCES player_assessments(id) ON DELETE SET NULL,
  player_attribute_assessment_id UUID                     REFERENCES player_attribute_assessments(id) ON DELETE SET NULL,

  external_reference           TEXT,
  description                  TEXT,
  metadata                     JSONB                      NOT NULL DEFAULT '{}'::jsonb,

  posted_at                    TIMESTAMPTZ,
  created_by                   UUID                       REFERENCES profiles(id) ON DELETE SET NULL,
  created_at                   TIMESTAMPTZ                NOT NULL DEFAULT NOW(),

  CONSTRAINT wallet_transactions_amount_nonzero_chk
    CHECK (amount <> 0),

  CONSTRAINT wallet_transactions_money_chk
    CHECK (
      (gross_amount IS NULL OR gross_amount >= 0)
      AND (playpro_net_amount IS NULL OR playpro_net_amount >= 0)
      AND (commission_amount IS NULL OR commission_amount >= 0)
    )
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type ON wallet_transactions(type);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_status ON wallet_transactions(status);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_player ON wallet_transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_organization ON wallet_transactions(organization_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at ON wallet_transactions(created_at DESC);

-- ============================================================
-- 6) ORGANIZATION VERIFICATIONS
-- PlayPro Verification Seal: RM1,000/year for academies/clubs/orgs.
-- Acts as trust engine for B2B credibility.
-- ============================================================

CREATE TABLE IF NOT EXISTS organization_verifications (
  id                    UUID                  PRIMARY KEY DEFAULT uuid_generate_v4(),

  organization_id        UUID                  NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  status                 verification_status   NOT NULL DEFAULT 'draft',

  seal_code              TEXT                  NOT NULL UNIQUE,
  package_name           TEXT                  NOT NULL DEFAULT 'Verified by PlayPro',
  fee_amount             NUMERIC(12,2)         NOT NULL DEFAULT 1000.00,
  currency               TEXT                  NOT NULL DEFAULT 'MYR',

  valid_from             DATE,
  valid_until            DATE                  NOT NULL,

  payment_reference      TEXT,
  paid_at                TIMESTAMPTZ,

  reviewed_by            UUID                  REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at            TIMESTAMPTZ,
  approved_by            UUID                  REFERENCES profiles(id) ON DELETE SET NULL,
  approved_at            TIMESTAMPTZ,

  rejection_reason       TEXT,
  suspension_reason      TEXT,

  checklist              JSONB                 NOT NULL DEFAULT '{}'::jsonb,
  documents              JSONB                 NOT NULL DEFAULT '[]'::jsonb,
  metadata               JSONB                 NOT NULL DEFAULT '{}'::jsonb,

  created_by             UUID                  REFERENCES profiles(id) ON DELETE SET NULL,
  created_at             TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ           NOT NULL DEFAULT NOW(),

  CONSTRAINT organization_verifications_dates_chk
    CHECK (valid_until >= COALESCE(valid_from, valid_until)),

  CONSTRAINT organization_verifications_fee_chk
    CHECK (fee_amount >= 0),

  -- One verification record per organization per annual period.
  UNIQUE (organization_id, valid_until)
);

CREATE INDEX IF NOT EXISTS idx_org_verifications_org ON organization_verifications(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_verifications_status ON organization_verifications(status);
CREATE INDEX IF NOT EXISTS idx_org_verifications_valid_until ON organization_verifications(valid_until);

-- ============================================================
-- END OF MODEL 6 CRITICAL INFRASTRUCTURE DDL
-- ============================================================

-- ============================================================
-- 7) ROW LEVEL SECURITY (RLS)
-- Frontend talks directly to Supabase, so Model 6 infrastructure
-- tables must be locked by default.
-- ============================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_passports ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_verifications ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- organizations RLS
-- Public can read active organizations only.
-- Owners/admins can read their own organizations.
-- Direct frontend writes are blocked; admin/RPC/service role should manage.
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "organizations_public_read_active" ON organizations;
CREATE POLICY "organizations_public_read_active"
  ON organizations
  FOR SELECT
  TO anon, authenticated
  USING (status = 'active');

DROP POLICY IF EXISTS "organizations_owner_admin_read" ON organizations;
CREATE POLICY "organizations_owner_admin_read"
  ON organizations
  FOR SELECT
  TO authenticated
  USING (
    owner_profile_id = auth.uid()
    OR admin_profile_id = auth.uid()
    OR created_by = auth.uid()
  );

-- ------------------------------------------------------------
-- player_passports RLS
-- Public/league-facing UI can read active passport status only.
-- Player owner can read own passport records through players.profile_id.
-- Direct frontend writes are blocked; renewal/approval must use RPC/admin.
-- NOTE: players.profile_id exists in current app usage. If a deployment has
-- an older players table without profile_id, apply the identity patch first.
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "player_passports_public_read_active" ON player_passports;
CREATE POLICY "player_passports_public_read_active"
  ON player_passports
  FOR SELECT
  TO anon, authenticated
  USING (status = 'active' AND status_aktif = true AND tarikh_tamat >= CURRENT_DATE);

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'players'
      AND column_name = 'profile_id'
  ) THEN
    DROP POLICY IF EXISTS "player_passports_owner_read" ON player_passports;
    CREATE POLICY "player_passports_owner_read"
      ON player_passports
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM players p
          WHERE p.id = player_passports.player_id
            AND p.profile_id = auth.uid()
        )
      );
  END IF;
END $$;

-- ------------------------------------------------------------
-- agent_wallets RLS
-- CRITICAL: Wallet can ONLY be read by the wallet owner.
-- No public reads. No direct frontend writes.
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "agent_wallets_owner_read_only" ON agent_wallets;
CREATE POLICY "agent_wallets_owner_read_only"
  ON agent_wallets
  FOR SELECT
  TO authenticated
  USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "agent_wallets_block_frontend_insert" ON agent_wallets;
CREATE POLICY "agent_wallets_block_frontend_insert"
  ON agent_wallets
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS "agent_wallets_block_frontend_update" ON agent_wallets;
CREATE POLICY "agent_wallets_block_frontend_update"
  ON agent_wallets
  FOR UPDATE
  TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "agent_wallets_block_frontend_delete" ON agent_wallets;
CREATE POLICY "agent_wallets_block_frontend_delete"
  ON agent_wallets
  FOR DELETE
  TO authenticated
  USING (false);

-- ------------------------------------------------------------
-- wallet_transactions RLS
-- READ-ONLY ledger for wallet owner.
-- Users cannot insert/update/delete transactions from frontend.
-- Money movement must go through service_role, trigger, or SECURITY DEFINER RPC.
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "wallet_transactions_wallet_owner_read_only" ON wallet_transactions;
CREATE POLICY "wallet_transactions_wallet_owner_read_only"
  ON wallet_transactions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM agent_wallets w
      WHERE w.id = wallet_transactions.wallet_id
        AND w.profile_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "wallet_transactions_block_frontend_insert" ON wallet_transactions;
CREATE POLICY "wallet_transactions_block_frontend_insert"
  ON wallet_transactions
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS "wallet_transactions_block_frontend_update" ON wallet_transactions;
CREATE POLICY "wallet_transactions_block_frontend_update"
  ON wallet_transactions
  FOR UPDATE
  TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "wallet_transactions_block_frontend_delete" ON wallet_transactions;
CREATE POLICY "wallet_transactions_block_frontend_delete"
  ON wallet_transactions
  FOR DELETE
  TO authenticated
  USING (false);

-- ------------------------------------------------------------
-- organization_verifications RLS
-- Public can read verified/non-expired seals.
-- Organization owner/admin can read all verification states for their org.
-- Direct frontend writes are blocked; review/approval through admin/RPC only.
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "organization_verifications_public_read_verified" ON organization_verifications;
CREATE POLICY "organization_verifications_public_read_verified"
  ON organization_verifications
  FOR SELECT
  TO anon, authenticated
  USING (status = 'verified' AND valid_until >= CURRENT_DATE);

DROP POLICY IF EXISTS "organization_verifications_owner_admin_read" ON organization_verifications;
CREATE POLICY "organization_verifications_owner_admin_read"
  ON organization_verifications
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM organizations o
      WHERE o.id = organization_verifications.organization_id
        AND (
          o.owner_profile_id = auth.uid()
          OR o.admin_profile_id = auth.uid()
          OR o.created_by = auth.uid()
        )
    )
  );

-- ============================================================
-- END OF MODEL 6 RLS
-- ============================================================

-- ============================================================
-- 8) PERFORMANCE INDEXES FOR RLS + FK PATHS
-- These are intentionally duplicated-safe. They protect RLS EXISTS checks
-- and Model 6 joins from becoming slow as data grows.
-- ============================================================

-- organizations FK / ownership paths
CREATE INDEX IF NOT EXISTS idx_model6_org_owner_profile_id ON organizations(owner_profile_id);
CREATE INDEX IF NOT EXISTS idx_model6_org_admin_profile_id ON organizations(admin_profile_id);
CREATE INDEX IF NOT EXISTS idx_model6_org_created_by ON organizations(created_by);
CREATE INDEX IF NOT EXISTS idx_model6_org_linked_club_id ON organizations(linked_club_id);
CREATE INDEX IF NOT EXISTS idx_model6_org_linked_league_id ON organizations(linked_league_id);

-- player_passports FK / eligibility paths
CREATE INDEX IF NOT EXISTS idx_model6_passports_player_id ON player_passports(player_id);
CREATE INDEX IF NOT EXISTS idx_model6_passports_season_id ON player_passports(season_id);
CREATE INDEX IF NOT EXISTS idx_model6_passports_league_id ON player_passports(league_id);
CREATE INDEX IF NOT EXISTS idx_model6_passports_verified_by ON player_passports(verified_by);
CREATE INDEX IF NOT EXISTS idx_model6_passports_active_lookup
  ON player_passports(player_id, season_id, status_aktif, tarikh_tamat);

-- agent_wallets FK / RLS paths
CREATE INDEX IF NOT EXISTS idx_model6_wallets_profile_id ON agent_wallets(profile_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallets_organization_id ON agent_wallets(organization_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallets_profile_status ON agent_wallets(profile_id, status);

-- wallet_transactions FK / ledger paths
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_wallet_created_at
  ON wallet_transactions(wallet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_player_id ON wallet_transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_organization_id ON wallet_transactions(organization_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_passport_id ON wallet_transactions(related_passport_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_player_assessment_id ON wallet_transactions(player_assessment_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_attr_assessment_id ON wallet_transactions(player_attribute_assessment_id);
CREATE INDEX IF NOT EXISTS idx_model6_wallet_tx_status_type ON wallet_transactions(status, type);

-- organization_verifications FK / public seal paths
CREATE INDEX IF NOT EXISTS idx_model6_org_verify_org_id ON organization_verifications(organization_id);
CREATE INDEX IF NOT EXISTS idx_model6_org_verify_reviewed_by ON organization_verifications(reviewed_by);
CREATE INDEX IF NOT EXISTS idx_model6_org_verify_approved_by ON organization_verifications(approved_by);
CREATE INDEX IF NOT EXISTS idx_model6_org_verify_public_lookup
  ON organization_verifications(organization_id, status, valid_until);

-- Existing table indexes needed by Model 6 RLS policies.
-- These are safe if the columns already exist.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'players'
      AND column_name = 'profile_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_model6_players_profile_id ON players(profile_id);
  END IF;
END $$;

-- ============================================================
-- 9) CONTROLLED RPC: process_assessment_payment
-- SECURITY DEFINER function for RM150 assessment payment flow.
-- Frontend must NOT insert/update wallet rows directly.
-- This RPC performs wallet creation, wallet balance update, and ledger insert
-- atomically inside PostgreSQL.
--
-- Business draft:
--   gross assessment payment: RM150
--   assessor/ejen wallet credit: RM125
--   platform/ops remainder: RM25
-- ============================================================

CREATE OR REPLACE FUNCTION process_assessment_payment(
  p_player_id UUID,
  p_assessor_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wallet_id UUID;
  v_tx_id UUID;
  v_wallet_code TEXT;
  v_gross_amount NUMERIC(14,2) := 150.00;
  v_assessor_credit NUMERIC(14,2) := 125.00;
  v_platform_amount NUMERIC(14,2) := 25.00;
BEGIN
  -- Validate player exists.
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id) THEN
    RAISE EXCEPTION 'PLAYER_NOT_FOUND: %', p_player_id
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate assessor profile exists.
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_assessor_id) THEN
    RAISE EXCEPTION 'ASSESSOR_PROFILE_NOT_FOUND: %', p_assessor_id
      USING ERRCODE = 'P0001';
  END IF;

  -- Find or create assessor wallet.
  SELECT id
    INTO v_wallet_id
  FROM agent_wallets
  WHERE profile_id = p_assessor_id
    AND status = 'active'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_wallet_id IS NULL THEN
    v_wallet_code := 'WAL-' || replace(p_assessor_id::TEXT, '-', '');

    INSERT INTO agent_wallets (
      profile_id,
      wallet_code,
      status,
      currency,
      available_balance,
      pending_balance,
      lifetime_earned,
      lifetime_paid_out,
      created_by,
      metadata
    ) VALUES (
      p_assessor_id,
      v_wallet_code,
      'active',
      'MYR',
      0.00,
      0.00,
      0.00,
      0.00,
      p_assessor_id,
      jsonb_build_object('created_by_rpc', 'process_assessment_payment')
    )
    RETURNING id INTO v_wallet_id;
  END IF;

  -- Lock wallet row before balance mutation.
  PERFORM 1
  FROM agent_wallets
  WHERE id = v_wallet_id
  FOR UPDATE;

  -- Credit assessor/ejen wallet.
  UPDATE agent_wallets
  SET available_balance = available_balance + v_assessor_credit,
      lifetime_earned = lifetime_earned + v_assessor_credit,
      updated_at = NOW()
  WHERE id = v_wallet_id;

  -- Insert immutable ledger transaction.
  INSERT INTO wallet_transactions (
    wallet_id,
    type,
    status,
    amount,
    currency,
    gross_amount,
    playpro_net_amount,
    commission_amount,
    player_id,
    external_reference,
    description,
    metadata,
    posted_at,
    created_by
  ) VALUES (
    v_wallet_id,
    'assessor_commission',
    'posted',
    v_assessor_credit,
    'MYR',
    v_gross_amount,
    v_platform_amount,
    v_assessor_credit,
    p_player_id,
    'assessment_payment:' || p_player_id::TEXT || ':' || p_assessor_id::TEXT || ':' || extract(epoch from NOW())::TEXT,
    'RM150 assessment payment processed; RM125 credited to assessor wallet.',
    jsonb_build_object(
      'rpc', 'process_assessment_payment',
      'gross_amount', v_gross_amount,
      'assessor_credit', v_assessor_credit,
      'platform_amount', v_platform_amount
    ),
    NOW(),
    p_assessor_id
  )
  RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object(
    'ok', true,
    'wallet_id', v_wallet_id,
    'transaction_id', v_tx_id,
    'gross_amount', v_gross_amount,
    'assessor_credit', v_assessor_credit,
    'platform_amount', v_platform_amount
  );
END;
$$;

REVOKE ALL ON FUNCTION process_assessment_payment(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION process_assessment_payment(UUID, UUID) TO authenticated;

-- ============================================================
-- END OF MODEL 6 SPRINT 1 SAFE EXECUTION ADDITIONS
-- ============================================================
