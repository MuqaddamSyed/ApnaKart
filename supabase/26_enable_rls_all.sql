-- ============================================================
-- ENFORCE RLS ON EVERY PUBLIC TABLE
-- Run in the Supabase SQL editor. Idempotent + safe.
--
-- Fixes the "rls_disabled_in_public" security advisory: a table whose
-- `enable row level security` never ran is readable/writable by anyone with
-- the (public) anon key. Every table here already has RLS policies, so
-- enabling RLS only ACTIVATES the protection already written — it does not
-- change app behaviour. `if exists` keeps it safe for not-yet-created tables.
--
-- Verify afterwards:
--   select tablename, rowsecurity from pg_tables
--   where schemaname = 'public' order by rowsecurity, tablename;
-- ============================================================
alter table if exists users             enable row level security;
alter table if exists suppliers         enable row level security;
alter table if exists customers         enable row level security;
alter table if exists addresses         enable row level security;
alter table if exists products          enable row level security;
alter table if exists delivery_agents   enable row level security;
alter table if exists orders            enable row level security;
alter table if exists order_items       enable row level security;
alter table if exists notifications     enable row level security;
alter table if exists phone_reuse_flags enable row level security;
alter table if exists device_tokens     enable row level security;
alter table if exists order_sessions    enable row level security;
alter table if exists order_item_status enable row level security;
alter table if exists session_handoff   enable row level security;
alter table if exists order_events      enable row level security;
alter table if exists skus              enable row level security;
