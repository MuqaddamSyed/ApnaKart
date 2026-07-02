-- ============================================================
-- FULL RESET — deletes ALL app data so you can test from scratch.
-- Run in the Supabase SQL editor. This is destructive.
--
-- What it clears:
--   • every public table (users, customers, suppliers, delivery_agents,
--     addresses, products, orders, order_items, order_sessions,
--     order_item_status, notifications, device_tokens, phone_reuse_flags)
--   • every auth user (so emails + phone numbers are free to reuse)
--
-- It does NOT touch: schema, RLS policies, storage buckets/policies,
-- email templates, or SMTP config.
-- ============================================================

-- 1. Wipe all application tables (CASCADE handles child rows/FKs).
--    Includes the v2 tables (order_sessions, order_item_status) so no
--    orphaned session/packing data is left behind.
truncate table
  order_item_status,
  order_items,
  orders,
  order_sessions,
  products,
  addresses,
  customers,
  suppliers,
  delivery_agents,
  notifications,
  device_tokens,
  phone_reuse_flags,
  users
restart identity cascade;

-- 2. Remove every auth user (frees up emails & phone numbers for re-signup).
delete from auth.users;

-- ------------------------------------------------------------
-- OPTIONAL: also clear uploaded product images from storage.
-- Uncomment to run. (Bucket + policies remain; only files are removed.)
-- ------------------------------------------------------------
-- delete from storage.objects where bucket_id = 'product-images';

-- ------------------------------------------------------------
-- After running this, re-create your ADMIN account (it was deleted):
--   1) Authentication → Users → Add user → email + password + Auto Confirm
--   2) then run:
--      insert into users (id, phone, email, name, role)
--      select id, '+910000000001', email, 'Admin', 'admin'
--      from auth.users where email = 'YOUR_ADMIN_EMAIL'
--      on conflict (id) do update set role = 'admin';
-- ------------------------------------------------------------
