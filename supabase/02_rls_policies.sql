-- ============================================================
-- QuickKart Row Level Security. Run after 01_schema.sql.
-- Assumes Supabase auth.uid() == users.id (same uuid).
-- ============================================================
alter table users            enable row level security;
alter table suppliers        enable row level security;
alter table customers        enable row level security;
alter table addresses        enable row level security;
alter table products         enable row level security;
alter table delivery_agents  enable row level security;
alter table orders           enable row level security;
alter table order_items      enable row level security;
alter table notifications    enable row level security;
alter table phone_reuse_flags enable row level security;

-- Helper: is the current user an admin?
create or replace function is_admin() returns boolean as $$
  select exists(select 1 from users where id = auth.uid() and role = 'admin');
$$ language sql stable security definer;

-- USERS: read/update own row; admin all
drop policy if exists users_self on users;
create policy users_self on users
  for all using (id = auth.uid() or is_admin())
  with check (id = auth.uid() or is_admin());

-- CUSTOMERS: own row only; admin all
drop policy if exists customers_self on customers;
create policy customers_self on customers
  for all using (id = auth.uid() or is_admin())
  with check (id = auth.uid() or is_admin());

-- ADDRESSES: owner only
drop policy if exists addresses_owner on addresses;
create policy addresses_owner on addresses
  for all using (customer_id = auth.uid() or is_admin())
  with check (customer_id = auth.uid() or is_admin());

-- SUPPLIERS: anyone can read verified; owner edits own; admin all
drop policy if exists suppliers_read on suppliers;
create policy suppliers_read on suppliers
  for select using (is_verified = true or id = auth.uid() or is_admin());
drop policy if exists suppliers_write on suppliers;
create policy suppliers_write on suppliers
  for update using (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  )
  with check (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  );
drop policy if exists suppliers_insert on suppliers;
create policy suppliers_insert on suppliers
  for insert with check (id = auth.uid() or is_admin());

-- PRODUCTS: anyone reads available; only owning supplier writes; admin all
drop policy if exists products_read on products;
create policy products_read on products
  for select using (
    is_available = true
    or supplier_id = auth.uid()
    or is_admin()
  );
drop policy if exists products_write on products;
create policy products_write on products
  for all using (
    is_admin()
    or exists (
      select 1 from suppliers s
      where s.id = products.supplier_id
        and s.id = auth.uid()
        and s.is_verified = true
    )
  )
  with check (
    is_admin()
    or exists (
      select 1 from suppliers s
      where s.id = products.supplier_id
        and s.id = auth.uid()
        and s.is_verified = true
    )
  );

-- DELIVERY AGENTS: owner updates own (esp. location); admin all; suppliers/customers read for assignment
drop policy if exists agents_read on delivery_agents;
create policy agents_read on delivery_agents
  for select using (true);   -- location needed by customer/admin maps
drop policy if exists agents_write on delivery_agents;
drop policy if exists agents_insert on delivery_agents;
drop policy if exists agents_update on delivery_agents;
create policy agents_insert on delivery_agents
  for insert with check (
    is_admin()
    or (id = auth.uid() and is_verified = false)
  );
create policy agents_update on delivery_agents
  for update using (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  )
  with check (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  );

-- ORDERS: customer own, supplier their orders, agent assigned, admin all
drop policy if exists orders_select on orders;
create policy orders_select on orders
  for select using (
    customer_id = auth.uid()
    or supplier_id = auth.uid()
    or delivery_id = auth.uid()
    or is_admin()
  );
drop policy if exists orders_insert on orders;
create policy orders_insert on orders
  for insert with check (customer_id = auth.uid() or is_admin());
drop policy if exists orders_update on orders;
create policy orders_update on orders
  for update using (
    customer_id = auth.uid()
    or supplier_id = auth.uid()
    or delivery_id = auth.uid()
    or is_admin()
  );

-- ORDER ITEMS: visible to any party on the parent order
drop policy if exists order_items_access on order_items;
create policy order_items_access on order_items
  for all using (
    exists (
      select 1 from orders o where o.id = order_items.order_id and (
        o.customer_id = auth.uid() or o.supplier_id = auth.uid()
        or o.delivery_id = auth.uid() or is_admin()
      )
    )
  )
  with check (
    exists (
      select 1 from orders o where o.id = order_items.order_id and (
        o.customer_id = auth.uid() or is_admin()
      )
    )
  );

-- NOTIFICATIONS: owner only
drop policy if exists notifications_owner on notifications;
create policy notifications_owner on notifications
  for all using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());

-- PHONE REUSE FLAGS: admin review only
drop policy if exists phone_reuse_flags_admin_read on phone_reuse_flags;
create policy phone_reuse_flags_admin_read on phone_reuse_flags
  for select using (is_admin());
