CREATE TABLE IF NOT EXISTS users (
  id text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS plaid_items (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users(id),
  plaid_item_id text NOT NULL,
  institution_id text NULL,
  institution_name text NULL,
  encrypted_access_token text NOT NULL,
  access_token_iv text NOT NULL,
  access_token_tag text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  disconnected_at timestamptz NULL,
  UNIQUE (user_id, plaid_item_id)
);

CREATE INDEX IF NOT EXISTS idx_plaid_items_user_active
  ON plaid_items (user_id)
  WHERE disconnected_at IS NULL;
