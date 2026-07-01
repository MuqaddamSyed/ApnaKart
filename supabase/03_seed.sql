-- ============================================================
-- Optional demo seed. Run after schema + RLS (use service role
-- in SQL editor; RLS is bypassed for the postgres/owner role).
-- Coordinates are around Davangere, Karnataka (a Tier-2 town).
-- ============================================================
-- Supplier user + profile
insert into users (id, phone, name, role) values
  ('11111111-1111-1111-1111-111111111111','+919000000001','Sri Krishna Stores','supplier')
on conflict (id) do nothing;
insert into suppliers (id, shop_name, address, lat, lng, category, is_verified, is_open, rating) values
  ('11111111-1111-1111-1111-111111111111','Sri Krishna Stores','MG Road, Davangere',14.4644,75.9218, array['groceries','fruits'], true, true, 4.5)
on conflict (id) do nothing;

-- Products
insert into products (supplier_id, name, category, mrp, sale_price, stock_qty, unit, image_url) values
  ('11111111-1111-1111-1111-111111111111','Aashirvaad Atta','groceries',320,275,40,'5kg',null),
  ('11111111-1111-1111-1111-111111111111','Amul Milk','groceries',30,28,100,'500ml',null),
  ('11111111-1111-1111-1111-111111111111','Bananas','fruits',60,42,30,'1dozen',null),
  ('11111111-1111-1111-1111-111111111111','Tata Salt','groceries',28,25,80,'1kg',null)
on conflict do nothing;

-- Customer
insert into users (id, phone, name, role) values
  ('22222222-2222-2222-2222-222222222222','+919000000002','Ravi Kumar','customer')
on conflict (id) do nothing;
insert into customers (id, default_address, default_lat, default_lng) values
  ('22222222-2222-2222-2222-222222222222','Vidyanagar, Davangere',14.4700,75.9250)
on conflict (id) do nothing;

-- Delivery agent
insert into users (id, phone, name, role) values
  ('33333333-3333-3333-3333-333333333333','+919000000003','Manjunath','delivery')
on conflict (id) do nothing;
insert into delivery_agents (id, is_available, current_lat, current_lng, vehicle_type) values
  ('33333333-3333-3333-3333-333333333333', true, 14.4660, 75.9230, 'bike')
on conflict (id) do nothing;

-- Admin
insert into users (id, phone, name, role) values
  ('44444444-4444-4444-4444-444444444444','+919000000004','Admin','admin')
on conflict (id) do nothing;
