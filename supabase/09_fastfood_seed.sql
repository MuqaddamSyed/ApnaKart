-- ============================================================
-- Fast Food seed: 3 suppliers + 13 orderable products.
-- Run in the Supabase SQL editor (service role bypasses the
-- approval trigger, so is_verified=true is allowed here).
-- Re-running creates duplicates — run once.
-- ============================================================

with s1 as (
  insert into users (id, phone, email, name, role)
  values (gen_random_uuid(), '+919900000011', 'chaatcorner@quickkart.local', 'Chaat Corner', 'supplier')
  returning id
),
s2 as (
  insert into users (id, phone, email, name, role)
  values (gen_random_uuid(), '+919900000012', 'pakodepoint@quickkart.local', 'Pakode Point', 'supplier')
  returning id
),
s3 as (
  insert into users (id, phone, email, name, role)
  values (gen_random_uuid(), '+919900000013', 'quickbites@quickkart.local', 'QuickBites', 'supplier')
  returning id
),
sup1 as (
  insert into suppliers (id, shop_name, address, lat, lng, category, is_verified, is_open)
  select id, 'Chaat Corner', 'MG Road, Davangere', 14.4644, 75.9218, array['Fast Food'], true, true from s1
  returning id
),
sup2 as (
  insert into suppliers (id, shop_name, address, lat, lng, category, is_verified, is_open)
  select id, 'Pakode Point', 'PJ Extension, Davangere', 14.4655, 75.9240, array['Fast Food'], true, true from s2
  returning id
),
sup3 as (
  insert into suppliers (id, shop_name, address, lat, lng, category, is_verified, is_open)
  select id, 'QuickBites', 'Vidyanagar, Davangere', 14.4670, 75.9260, array['Fast Food'], true, true from s3
  returning id
)
insert into products (supplier_id, name, category, unit, mrp, sale_price, stock_qty, is_available)
select sid, name, 'Fast Food', unit, price, price, 50, true
from (
  select (select id from sup1) as sid, 'Masala Puri'    as name, 'plate' as unit, 50  as price
  union all select (select id from sup1), 'Mirchi Bhajji',   'plate',  30
  union all select (select id from sup1), 'Alo Bonde',       'plate',  30
  union all select (select id from sup2), 'Pakode',          'plate',  40
  union all select (select id from sup3), 'Bhel Puri',       'plate',  40
  union all select (select id from sup3), 'Veg Burger',      'piece',  70
  union all select (select id from sup3), 'Chicken Burger',  'piece', 110
  union all select (select id from sup3), 'Veg Pizza',       'piece', 150
  union all select (select id from sup3), 'Corn Pizza',      'piece', 170
  union all select (select id from sup3), 'Chicken Pizza',   'piece', 220
  union all select (select id from sup3), 'French Fries',    'plate',  80
  union all select (select id from sup3), 'Veg Nuggets',     'plate',  90
  union all select (select id from sup3), 'Chicken Nuggets', 'plate', 120
) t;
