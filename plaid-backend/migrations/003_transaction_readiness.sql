ALTER TABLE plaid_items
  ADD COLUMN IF NOT EXISTS historical_ready_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS historical_recovery_started_at timestamptz NULL;
