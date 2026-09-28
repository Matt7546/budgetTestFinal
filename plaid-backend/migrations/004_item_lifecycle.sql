ALTER TABLE users
  ADD COLUMN IF NOT EXISTS item_lifecycle_generation bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS item_lifecycle_state text NOT NULL DEFAULT 'active';

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;

CREATE TABLE IF NOT EXISTS plaid_item_exchange_leases (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id),
  generation bigint NOT NULL,
  state text NOT NULL DEFAULT 'prepared',
  public_token_sha256 text NULL,
  link_session_id text NULL,
  plaid_item_id text NULL,
  encrypted_access_token text NULL,
  access_token_iv text NULL,
  access_token_tag text NULL,
  provider_request_id text NULL,
  removal_request_id text NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE plaid_item_exchange_leases
  ADD COLUMN IF NOT EXISTS state text NOT NULL DEFAULT 'prepared',
  ADD COLUMN IF NOT EXISTS public_token_sha256 text NULL,
  ADD COLUMN IF NOT EXISTS link_session_id text NULL,
  ADD COLUMN IF NOT EXISTS plaid_item_id text NULL,
  ADD COLUMN IF NOT EXISTS encrypted_access_token text NULL,
  ADD COLUMN IF NOT EXISTS access_token_iv text NULL,
  ADD COLUMN IF NOT EXISTS access_token_tag text NULL,
  ADD COLUMN IF NOT EXISTS provider_request_id text NULL,
  ADD COLUMN IF NOT EXISTS removal_request_id text NULL;

CREATE INDEX IF NOT EXISTS idx_plaid_item_exchange_leases_user
  ON plaid_item_exchange_leases(user_id);

CREATE TABLE IF NOT EXISTS plaid_item_removal_recoveries (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id),
  plaid_item_id text NOT NULL,
  encrypted_access_token text NOT NULL,
  access_token_iv text NOT NULL,
  access_token_tag text NOT NULL,
  exchange_lease_id text NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE plaid_item_removal_recoveries
  ADD COLUMN IF NOT EXISTS exchange_lease_id text NULL;

CREATE INDEX IF NOT EXISTS idx_plaid_item_removal_recoveries_user
  ON plaid_item_removal_recoveries(user_id);
