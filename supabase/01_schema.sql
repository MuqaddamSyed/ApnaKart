-- ============================================================
-- QuickKart schema (migration-ready). Run first.
-- ============================================================
create extension if not exists postgis;

-- USERS --------------------------------------------------------
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  phone text unique not null,
  email text unique,
  name text,
  role text check (role in ('customer','supplier','delivery','admin')),
  is_active boolean default true,
  created_at timestamptz default now()
);

-- SUPPLIERS ----------------------------------------------------
create table if not exists suppliers (
  id uuid primary key references users(id) on delete cascade,
  shop_name text not null,
  address text,
  lat double precision,
  lng double precision,
  category text[],                 -- ['groceries','fast_food']
  is_verified boolean default false,
  is_open boolean default true,
  rating double precision default 0.0
);

-- CUSTOMERS ----------------------------------------------------
create table if not exists customers (
  id uuid primary key references users(id) on delete cascade,
  default_address text,
  default_lat double precision,
  default_lng double precision
);

-- ADDRESSES ----------------------------------------------------
create table if not exists addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references customers(id) on delete cascade,
  label text,                      -- 'Home','Work'
  full_address text,
  lat double precision,
  lng double precision
);

-- PRODUCTS -----------------------------------------------------
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references suppliers(id) on delete cascade,
  name text not null,
  description text,
  image_url text,
  category text,
  mrp numeric(10,2) not null,
  sale_price numeric(10,2) not null,
  discount_percent int default 0,
  stock_qty int default 0,
  unit text,                       -- '500g','1L','piece'
  is_available boolean default true,
  created_at timestamptz default now()
);

-- DELIVERY AGENTS ---------------------------------------------
create table if not exists delivery_agents (
  id uuid primary key references users(id) on delete cascade,
  is_verified boolean default false,
  is_available boolean default false,
  current_lat double precision,
  current_lng double precision,
  vehicle_type text,               -- 'bike','cycle'
  total_deliveries int default 0,
  earnings_today numeric(10,2) default 0
);

-- ORDERS -------------------------------------------------------
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references customers(id),
  supplier_id uuid references suppliers(id),
  delivery_id uuid references users(id),
  status text check (status in (
    'placed','confirmed','preparing','picked_up','on_the_way','delivered','cancelled'
  )) default 'placed',
  payment_method text default 'COD',
  payment_status text default 'pending',
  subtotal numeric(10,2),
  delivery_fee numeric(10,2) default 20.00,
  total numeric(10,2),
  delivery_address text,
  delivery_lat double precision,
  delivery_lng double precision,
  otp text,                        -- hashed 4-digit delivery OTP
  notes text,
  placed_at timestamptz default now(),
  delivered_at timestamptz
);

-- ORDER ITEMS --------------------------------------------------
create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade,
  product_id uuid references products(id),
  quantity int not null,
  unit_price numeric(10,2),
  total_price numeric(10,2)
);

-- NOTIFICATIONS LOG -------------------------------------------
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  title text,
  body text,
  type text,
  is_read boolean default false,
  created_at timestamptz default now()
);

-- PHONE REUSE FLAGS -------------------------------------------
create table if not exists phone_reuse_flags (
  id uuid primary key default gen_random_uuid(),
  attempted_user_id uuid,
  attempted_email text not null,
  attempted_phone text not null,
  existing_user_id uuid,
  existing_email text,
  existing_phone text,
  existing_name text,
  existing_role text,
  reason text check (reason in ('phone_already_registered','phone_change_attempt')),
  created_at timestamptz default now()
);

-- Helpful indexes ---------------------------------------------
create index if not exists idx_products_supplier on products(supplier_id);
create index if not exists idx_orders_customer on orders(customer_id);
create index if not exists idx_orders_supplier on orders(supplier_id);
create index if not exists idx_orders_delivery on orders(delivery_id);
create index if not exists idx_order_items_order on order_items(order_id);

-- ============================================================
-- Triggers / functions
-- ============================================================

-- Auto-compute discount_percent on products
create or replace function set_discount_percent() returns trigger as $$
begin
  if new.mrp is not null and new.mrp > 0 then
    new.discount_percent := round(((new.mrp - new.sale_price) / new.mrp) * 100);
  else
    new.discount_percent := 0;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_set_discount on products;
create trigger trg_set_discount before insert or update of mrp, sale_price
  on products for each row execute function set_discount_percent();

-- Stamp delivered_at when status flips to delivered
create or replace function stamp_delivered() returns trigger as $$
begin
  if new.status = 'delivered' and (old.status is distinct from 'delivered') then
    new.delivered_at := now();
    new.payment_status := 'paid';   -- COD collected on delivery
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_delivered on orders;
create trigger trg_stamp_delivered before update of status
  on orders for each row execute function stamp_delivered();

-- ============================================================
-- Supplier discovery within radius (PostGIS). Called via RPC.
--   select * from nearby_suppliers(userLng, userLat, 5000);
-- ============================================================
create or replace function nearby_suppliers(
  user_lng double precision,
  user_lat double precision,
  radius_m double precision default 5000
)
returns setof suppliers as $$
  select s.* from suppliers s
  where s.is_open = true
    and s.is_verified = true
    and s.lat is not null and s.lng is not null
    and ST_DWithin(
      ST_MakePoint(s.lng, s.lat)::geography,
      ST_MakePoint(user_lng, user_lat)::geography,
      radius_m
    )
  order by ST_Distance(
    ST_MakePoint(s.lng, s.lat)::geography,
    ST_MakePoint(user_lng, user_lat)::geography
  );
$$ language sql stable;
