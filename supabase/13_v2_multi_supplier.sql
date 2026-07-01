-- ============================================================
-- V2: Multi-supplier orders, packing screen, order sessions.
-- Run ONCE in Supabase SQL editor after migrations 01–12.
-- ============================================================

-- ----------------------------------------------------------------
-- 1. ORDER SESSIONS
--    One per customer checkout. Holds the delivery assignment and
--    the top-level status. Individual supplier sub-orders live in
--    the existing `orders` table (with session_id foreign key).
-- ----------------------------------------------------------------
create table if not exists order_sessions (
  id            uuid primary key default gen_random_uuid(),
  display_id    text unique,
  customer_id   uuid references customers(id),
  delivery_id   uuid references users(id),
  status        text check (status in (
    'waiting_suppliers','all_confirmed','out_for_delivery','delivered','cancelled'
  )) default 'waiting_suppliers',
  delivery_address text,
  delivery_lat  double precision,
  delivery_lng  double precision,
  delivery_fee  numeric(10,2) default 20.00,
  total         numeric(10,2) default 0,
  placed_at     timestamptz default now(),
  delivered_at  timestamptz
);

-- Add session_id to existing orders table (backward-compatible: nullable).
alter table orders add column if not exists session_id uuid references order_sessions(id) on delete cascade;

-- Index for fast session → sub-order lookups.
create index if not exists idx_orders_session on orders(session_id);
create index if not exists idx_sessions_customer on order_sessions(customer_id);
create index if not exists idx_sessions_delivery on order_sessions(delivery_id);

-- ----------------------------------------------------------------
-- 2. ORDER ITEM STATUS
--    Supplier ticks/crosses each item during packing. Final amount
--    is recalculated from actually available items.
-- ----------------------------------------------------------------
create table if not exists order_item_status (
  id              uuid primary key default gen_random_uuid(),
  order_item_id   uuid references order_items(id) on delete cascade unique,
  is_available    boolean default true,
  available_qty   int,              -- null = full qty available
  updated_at      timestamptz default now()
);

create index if not exists idx_item_status_item on order_item_status(order_item_id);

-- ----------------------------------------------------------------
-- 3. DISPLAY ID  (format: DDMM + 3-digit daily count, e.g. 0207001)
--    Auto-generated on insert. Uses count of sessions today to
--    create a sequential number per day.
-- ----------------------------------------------------------------
create or replace function generate_session_display_id()
returns trigger language plpgsql as $$
declare
  v_seq int;
begin
  select count(*) + 1 into v_seq
  from order_sessions
  where placed_at::date = current_date;

  new.display_id := to_char(now(), 'DDMM') || lpad(v_seq::text, 3, '0');
  return new;
end;
$$;

drop trigger if exists trg_session_display_id on order_sessions;
create trigger trg_session_display_id
  before insert on order_sessions
  for each row execute function generate_session_display_id();

-- ----------------------------------------------------------------
-- 4. SESSION AUTO-ADVANCE
--    When every sub-order in a session reaches 'confirmed',
--    flip the session to 'all_confirmed' and fire push to agents.
-- ----------------------------------------------------------------
create or replace function check_session_ready()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  v_session uuid;
  v_pending int;
begin
  v_session := new.session_id;
  if v_session is null then return new; end if;

  select count(*) into v_pending
  from orders
  where session_id = v_session
    and status not in ('confirmed','cancelled');

  -- All remaining (non-cancelled) orders are confirmed.
  if v_pending = 0 then
    update order_sessions
    set status = 'all_confirmed'
    where id = v_session
      and status = 'waiting_suppliers';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_session_ready on orders;
create trigger trg_check_session_ready
  after update of status on orders
  for each row execute function check_session_ready();

-- ----------------------------------------------------------------
-- 5. CLAIM SESSION
--    Delivery agent atomically claims an unclaimed session.
--    Returns true if claimed, false if another agent was faster.
-- ----------------------------------------------------------------
create or replace function claim_session(p_session_id uuid, p_agent_id uuid)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_rows int;
begin
  update order_sessions
  set delivery_id = p_agent_id,
      status = 'out_for_delivery'
  where id = p_session_id
    and delivery_id is null
    and status = 'all_confirmed';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke all on function claim_session(uuid, uuid) from public, anon;
grant execute on function claim_session(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------
-- 6. COMPLETE SESSION DELIVERY
--    Marks session + all sub-orders delivered, credits agent.
-- ----------------------------------------------------------------
create or replace function complete_session_delivery(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_agent uuid;
  v_fee numeric;
begin
  select delivery_id, delivery_fee into v_agent, v_fee
  from order_sessions where id = p_session_id;

  if v_agent is null then
    raise exception 'session has no assigned delivery agent';
  end if;
  if auth.uid() <> v_agent and not is_admin() then
    raise exception 'only the assigned agent can complete this delivery';
  end if;

  -- Mark session delivered.
  update order_sessions
  set status = 'delivered', delivered_at = now()
  where id = p_session_id;

  -- Mark every sub-order delivered (triggers trg_stamp_delivered on each).
  update orders
  set status = 'delivered'
  where session_id = p_session_id
    and status not in ('cancelled','returned');

  -- Credit agent earnings.
  update delivery_agents
  set earnings_today    = coalesce(earnings_today, 0) + coalesce(v_fee, 0),
      total_deliveries  = coalesce(total_deliveries, 0) + 1
  where id = v_agent;
end;
$$;

revoke all on function complete_session_delivery(uuid) from public, anon;
grant execute on function complete_session_delivery(uuid) to authenticated;

-- ----------------------------------------------------------------
-- 7. REJECT SESSION BY CUSTOMER
-- ----------------------------------------------------------------
create or replace function reject_session_by_customer(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  update order_sessions set status = 'cancelled' where id = p_session_id;
  update orders set status = 'returned'
  where session_id = p_session_id and status not in ('cancelled','delivered','returned');
end;
$$;

revoke all on function reject_session_by_customer(uuid) from public, anon;
grant execute on function reject_session_by_customer(uuid) to authenticated;

-- ----------------------------------------------------------------
-- 8. TODAY'S SUPPLIER EARNINGS
--    Sum of subtotals for delivered orders placed today.
-- ----------------------------------------------------------------
create or replace function get_today_supplier_earnings(p_supplier_id uuid)
returns numeric language sql stable security definer
set search_path = public as $$
  select coalesce(sum(subtotal), 0)
  from orders
  where supplier_id = p_supplier_id
    and status = 'delivered'
    and placed_at::date = current_date;
$$;

revoke all on function get_today_supplier_earnings(uuid) from public, anon;
grant execute on function get_today_supplier_earnings(uuid) to authenticated;

-- ----------------------------------------------------------------
-- 9. PRODUCT CATALOG: admin_managed flag
--    When true, supplier can only edit sale_price and is_available.
-- ----------------------------------------------------------------
alter table products add column if not exists admin_managed boolean default false;

-- ----------------------------------------------------------------
-- 10. USERS: ensure phone column exists (already in schema, but safe)
-- ----------------------------------------------------------------
-- phone already exists in users table from 01_schema.sql

-- ----------------------------------------------------------------
-- 11. ROW-LEVEL SECURITY for new tables
-- ----------------------------------------------------------------

-- order_sessions: customer sees own, delivery agent sees assigned,
-- supplier sees sessions containing their orders, admin sees all.
alter table order_sessions enable row level security;

drop policy if exists "session_select" on order_sessions;
create policy "session_select" on order_sessions for select
  using (
    auth.uid() = customer_id
    or auth.uid() = delivery_id
    or exists (
      select 1 from orders o
      where o.session_id = order_sessions.id
        and o.supplier_id = auth.uid()
    )
    or is_admin()
  );

drop policy if exists "session_insert" on order_sessions;
create policy "session_insert" on order_sessions for insert
  with check (auth.uid() = customer_id);

drop policy if exists "session_update_agent" on order_sessions;
create policy "session_update_agent" on order_sessions for update
  using (
    auth.uid() = delivery_id
    or auth.uid() = customer_id
    or is_admin()
  );

-- order_item_status: supplier of the parent order can upsert.
alter table order_item_status enable row level security;

drop policy if exists "item_status_select" on order_item_status;
create policy "item_status_select" on order_item_status for select
  using (
    exists (
      select 1 from order_items oi
      join orders o on o.id = oi.order_id
      where oi.id = order_item_status.order_item_id
        and (o.supplier_id = auth.uid()
          or o.customer_id = auth.uid()
          or o.delivery_id = auth.uid()
          or is_admin())
    )
  );

drop policy if exists "item_status_upsert" on order_item_status;
create policy "item_status_upsert" on order_item_status for insert
  with check (
    exists (
      select 1 from order_items oi
      join orders o on o.id = oi.order_id
      where oi.id = order_item_status.order_item_id
        and o.supplier_id = auth.uid()
    )
  );

drop policy if exists "item_status_update" on order_item_status;
create policy "item_status_update" on order_item_status for update
  using (
    exists (
      select 1 from order_items oi
      join orders o on o.id = oi.order_id
      where oi.id = order_item_status.order_item_id
        and o.supplier_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------
-- DONE. Verify with:
--   select * from order_sessions limit 5;
--   select * from order_item_status limit 5;
--   select display_id, status from order_sessions order by placed_at desc limit 10;
-- ----------------------------------------------------------------
