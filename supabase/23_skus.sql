-- ============================================================
-- SKU CATALOG (admin-managed master products)
-- Run ONCE in the Supabase SQL editor. Idempotent.
--
-- A library of common products (name, image, category, optional price)
-- the admin can build up. EVERY column is nullable so the admin can save
-- an entry even without MRP / selling price.
-- ============================================================
create table if not exists skus (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  image_url   text,
  category    text,
  description text,
  mrp         numeric(10,2),
  sale_price  numeric(10,2),
  unit        text,
  created_at  timestamptz default now()
);

alter table skus enable row level security;

-- Anyone signed in can read the catalog; only admins can write it.
drop policy if exists skus_select on skus;
create policy skus_select on skus for select using (true);

drop policy if exists skus_write on skus;
create policy skus_write on skus for all
  using (is_admin()) with check (is_admin());
