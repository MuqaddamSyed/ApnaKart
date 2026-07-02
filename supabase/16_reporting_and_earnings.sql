-- ============================================================
-- REPORTING + EARNINGS
-- Run ONCE in the Supabase SQL editor AFTER migrations 13–15.
-- Safe to re-run (CREATE OR REPLACE everywhere).
--
-- Adds:
--   1. get_total_supplier_earnings()  — lifetime supplier earnings RPC
--      (powers the "Total Earnings" widget on the supplier dashboard).
--   2. A set of read-only tracking VIEWS so you can see every order,
--      session, item, supplier and agent — and daily sales — from one
--      place (Supabase SQL editor / Table editor / admin).
--
-- The views use `security_invoker = true`: when queried from the app
-- they respect the caller's RLS (admin sees all, a supplier only their
-- own). In the SQL editor you run as the owner, so you see EVERYTHING.
-- ============================================================

-- -------------------------------------------------------
-- 1. LIFETIME SUPPLIER EARNINGS RPC
-- -------------------------------------------------------
create or replace function get_total_supplier_earnings(p_supplier_id uuid)
returns numeric language plpgsql stable security definer
set search_path = public as $$
declare
  v_earnings numeric;
begin
  if auth.uid() <> p_supplier_id and not is_admin() then
    raise exception 'access denied';
  end if;

  select coalesce(sum(subtotal), 0) into v_earnings
  from orders
  where supplier_id = p_supplier_id
    and status = 'delivered';

  return v_earnings;
end;
$$;

revoke all on function get_total_supplier_earnings(uuid) from public, anon;
grant execute on function get_total_supplier_earnings(uuid) to authenticated;

-- -------------------------------------------------------
-- 2a. ORDER MASTER — one row per supplier sub-order, with the
--     session number, customer, supplier and agent all resolved.
-- -------------------------------------------------------
create or replace view v_order_master
with (security_invoker = true) as
select
  o.id              as order_id,
  o.session_id,
  sess.display_id   as order_no,
  o.status          as order_status,
  sess.status       as session_status,
  o.subtotal,
  o.delivery_fee,
  o.total           as order_total,
  o.payment_method,
  o.payment_status,
  o.placed_at,
  o.delivered_at,
  o.customer_id,
  cu.name           as customer_name,
  cu.phone          as customer_phone,
  o.supplier_id,
  sup.shop_name     as supplier_name,
  supu.phone        as supplier_phone,
  o.delivery_id,
  agu.name          as agent_name,
  agu.phone         as agent_phone,
  o.delivery_address
from orders o
left join order_sessions sess on sess.id = o.session_id
left join users cu   on cu.id = o.customer_id
left join suppliers sup on sup.id = o.supplier_id
left join users supu on supu.id = o.supplier_id
left join users agu  on agu.id = o.delivery_id;

-- -------------------------------------------------------
-- 2b. ORDER ITEM DETAIL — every line item with ordered vs
--     actually-packed quantity and amount.
-- -------------------------------------------------------
create or replace view v_order_item_detail
with (security_invoker = true) as
select
  oi.id             as order_item_id,
  oi.order_id,
  o.session_id,
  sess.display_id   as order_no,
  o.supplier_id,
  sup.shop_name     as supplier_name,
  p.name            as product_name,
  oi.quantity       as ordered_qty,
  ois.available_qty as packed_qty,
  coalesce(ois.is_available, true) as is_available,
  oi.unit_price,
  oi.total_price    as ordered_total,
  case when coalesce(ois.is_available, true)
       then oi.unit_price * coalesce(ois.available_qty, oi.quantity)
       else 0 end   as packed_total,
  o.status          as order_status,
  o.placed_at
from order_items oi
join orders o on o.id = oi.order_id
left join order_sessions sess on sess.id = o.session_id
left join suppliers sup on sup.id = o.supplier_id
left join products p on p.id = oi.product_id
left join order_item_status ois on ois.order_item_id = oi.id;

-- -------------------------------------------------------
-- 2c. SESSION MASTER — one row per customer checkout, with
--     shop count and the assigned agent.
-- -------------------------------------------------------
create or replace view v_session_master
with (security_invoker = true) as
select
  sess.id           as session_id,
  sess.display_id   as order_no,
  sess.status,
  sess.total,
  sess.delivery_fee,
  sess.delivery_address,
  sess.placed_at,
  sess.delivered_at,
  sess.customer_id,
  cu.name           as customer_name,
  cu.phone          as customer_phone,
  sess.delivery_id,
  agu.name          as agent_name,
  agu.phone         as agent_phone,
  (select count(*) from orders o where o.session_id = sess.id) as shop_count,
  (select count(*) from orders o
     where o.session_id = sess.id and o.status = 'confirmed') as confirmed_shops
from order_sessions sess
left join users cu  on cu.id = sess.customer_id
left join users agu on agu.id = sess.delivery_id;

-- -------------------------------------------------------
-- 2d. SUPPLIER EARNINGS — lifetime + today (IST), delivered.
-- -------------------------------------------------------
create or replace view v_supplier_earnings
with (security_invoker = true) as
select
  s.id          as supplier_id,
  s.shop_name   as supplier_name,
  u.phone       as supplier_phone,
  s.is_verified,
  s.is_open,
  count(o.id) filter (where o.status = 'delivered')                 as delivered_orders,
  coalesce(sum(o.subtotal) filter (where o.status = 'delivered'), 0) as lifetime_earnings,
  coalesce(sum(o.subtotal) filter (
    where o.status = 'delivered'
      and (o.placed_at at time zone 'Asia/Kolkata')::date
          = (now() at time zone 'Asia/Kolkata')::date
  ), 0)                                                             as today_earnings,
  count(o.id) filter (
    where o.status not in ('delivered', 'cancelled', 'returned')
  )                                                                 as active_orders
from suppliers s
left join users u on u.id = s.id
left join orders o on o.supplier_id = s.id
group by s.id, s.shop_name, u.phone, s.is_verified, s.is_open;

-- -------------------------------------------------------
-- 2e. AGENT EARNINGS — delivered sessions + delivery-fee income.
-- -------------------------------------------------------
create or replace view v_agent_earnings
with (security_invoker = true) as
select
  a.id            as agent_id,
  u.name          as agent_name,
  u.phone         as agent_phone,
  a.is_verified,
  a.is_available,
  a.total_deliveries,
  a.earnings_today,
  count(sess.id) filter (where sess.status = 'delivered')                    as delivered_sessions,
  coalesce(sum(sess.delivery_fee) filter (where sess.status = 'delivered'), 0) as lifetime_earnings
from delivery_agents a
left join users u on u.id = a.id
left join order_sessions sess on sess.delivery_id = a.id
group by a.id, u.name, u.phone, a.is_verified, a.is_available,
         a.total_deliveries, a.earnings_today;

-- -------------------------------------------------------
-- 2f. DAILY SALES — one row per IST day (newest first).
-- -------------------------------------------------------
create or replace view v_daily_sales
with (security_invoker = true) as
select
  (sess.placed_at at time zone 'Asia/Kolkata')::date              as sale_date,
  count(*)                                                        as sessions,
  count(*) filter (where sess.status = 'delivered')               as delivered_sessions,
  count(*) filter (where sess.status = 'cancelled')               as cancelled_sessions,
  coalesce(sum(sess.total) filter (where sess.status = 'delivered'), 0) as delivered_revenue
from order_sessions sess
group by (sess.placed_at at time zone 'Asia/Kolkata')::date
order by sale_date desc;

-- -------------------------------------------------------
-- Grants: let signed-in users read the views (RLS still filters
-- per-role via security_invoker). The SQL editor sees everything.
-- -------------------------------------------------------
grant select on
  v_order_master, v_order_item_detail, v_session_master,
  v_supplier_earnings, v_agent_earnings, v_daily_sales
to authenticated;

-- ------------------------------------------------------------
-- Quick tracking queries once this is applied:
--   select * from v_order_master order by placed_at desc;
--   select * from v_session_master order by placed_at desc;
--   select * from v_order_item_detail where order_no = '0207001';
--   select * from v_supplier_earnings order by lifetime_earnings desc;
--   select * from v_agent_earnings order by lifetime_earnings desc;
--   select * from v_daily_sales;
-- ------------------------------------------------------------
