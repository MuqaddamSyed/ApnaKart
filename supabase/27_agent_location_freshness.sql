-- ============================================================
-- AGENT LOCATION FRESHNESS
-- Run in the Supabase SQL editor. Idempotent.
--
-- The delivery app pings current_lat/lng every ~10s, but only while the
-- delivery screen is open. Without a timestamp, readers (customer tracking,
-- admin fleet map) can't tell a live pin from one frozen an hour ago.
-- ============================================================
alter table delivery_agents
  add column if not exists location_updated_at timestamptz;
