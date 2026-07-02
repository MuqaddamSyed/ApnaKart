-- ============================================================
-- V2 FIXES: security (IDOR), display_id race + IST timezone,
--           session-advance bug, recompute_session_total RPC,
--           session UPDATE WITH CHECK policy.
-- Run ONCE in Supabase SQL editor AFTER migrations 13 + 14.
-- Safe to re-run (idempotent: CREATE OR REPLACE / DROP..CREATE).
-- ============================================================

-- -------------------------------------------------------
-- 1. DISPLAY ID — race-safe + IST timezone
--    Old version used `select count(*)+1` (read-then-write
--    race → duplicate display_id under load). Now uses an
--    advisory lock + max(sequence) to be fully race-safe.
--    Timezone changed from UTC to Asia/Kolkata so DDMM and
--    the daily counter match Indian midnight, not UTC.
-- -------------------------------------------------------
create or replace function generate_session_display_id()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  v_seq   int;
  v_date  date;
  v_pfx   text;
begin
  v_date := (now() at time zone 'Asia/Kolkata')::date;
  v_pfx  := to_char(v_date, 'DDMM');

  -- Serialize within the same day using a transaction-scoped advisory lock
  -- keyed on the IST date as an epoch integer (no two transactions can hold
  -- the same lock simultaneously, so the count is race-free).
  perform pg_advisory_xact_lock(extract(epoch from v_date)::bigint);

  -- Find the highest sequence suffix already issued today.
  select coalesce(
    max((regexp_replace(display_id, '^' || v_pfx, ''))::int),
    0
  ) + 1
  into v_seq
  from order_sessions
  where display_id like v_pfx || '%'
    and (placed_at at time zone 'Asia/Kolkata')::date = v_date;

  new.display_id := v_pfx || lpad(v_seq::text, 3, '0');
  return new;
end;
$$;

drop trigger if exists trg_session_display_id on order_sessions;
create trigger trg_session_display_id
  before insert on order_sessions
  for each row execute function generate_session_display_id();

-- -------------------------------------------------------
-- 2. SESSION AUTO-ADVANCE — require ≥1 confirmed order
--    Old version: if all non-cancelled orders are gone
--    (i.e. every supplier rejected), it still advanced to
--    'all_confirmed'. Now cancels the session when all
--    suppliers reject, and only advances when ≥1 confirmed.
-- -------------------------------------------------------
create or replace function check_session_ready()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  v_session   uuid;
  v_pending   int;
  v_confirmed int;
begin
  v_session := new.session_id;
  if v_session is null then return new; end if;

  -- Orders still awaiting supplier decision (not yet confirmed or cancelled).
  select count(*) into v_pending
  from orders
  where session_id = v_session
    and status not in ('confirmed', 'cancelled');

  -- Orders the supplier already accepted.
  select count(*) into v_confirmed
  from orders
  where session_id = v_session
    and status = 'confirmed';

  if v_pending = 0 and v_confirmed > 0 then
    -- All non-cancelled orders are confirmed → ready for delivery.
    update order_sessions
    set status = 'all_confirmed'
    where id = v_session
      and status = 'waiting_suppliers';

  elsif v_pending = 0 and v_confirmed = 0 then
    -- Every supplier rejected → cancel the session so the customer is notified.
    update order_sessions
    set status = 'cancelled'
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

-- -------------------------------------------------------
-- 3. REJECT SESSION BY CUSTOMER — IDOR fix
--    Old version had no ownership check (CWE-639): any
--    authenticated user could cancel anyone's session by
--    guessing its UUID.
-- -------------------------------------------------------
create or replace function reject_session_by_customer(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_customer uuid;
begin
  select customer_id into v_customer
  from order_sessions where id = p_session_id;

  if v_customer is null then
    raise exception 'session not found';
  end if;
  if auth.uid() <> v_customer and not is_admin() then
    raise exception 'only the customer who placed the order can cancel this session';
  end if;

  update order_sessions set status = 'cancelled' where id = p_session_id;
  update orders set status = 'returned'
  where session_id = p_session_id
    and status not in ('cancelled', 'delivered', 'returned');
end;
$$;

revoke all on function reject_session_by_customer(uuid) from public, anon;
grant execute on function reject_session_by_customer(uuid) to authenticated;

-- -------------------------------------------------------
-- 4. CLAIM SESSION — identity + verified-agent check
--    Old version accepted any p_agent_id without checking
--    auth.uid() = p_agent_id, and didn't verify the agent.
--    Also stamps delivery_id on sub-orders so subsequent
--    order reads/updates pass RLS via delivery_id = auth.uid().
-- -------------------------------------------------------
create or replace function claim_session(p_session_id uuid, p_agent_id uuid)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_rows     int;
  v_verified boolean;
begin
  -- Caller must be the agent they claim to be.
  if auth.uid() <> p_agent_id then
    raise exception 'agent id must match the authenticated caller';
  end if;

  -- Agent must be verified before claiming deliveries.
  select is_verified into v_verified
  from delivery_agents where id = p_agent_id;

  if not coalesce(v_verified, false) then
    raise exception 'only verified delivery agents can claim sessions';
  end if;

  update order_sessions
  set delivery_id = p_agent_id,
      status      = 'out_for_delivery'
  where id          = p_session_id
    and delivery_id is null
    and status      = 'all_confirmed';

  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    -- Stamp every sub-order so the agent can read/update them via RLS.
    update orders
    set delivery_id = p_agent_id
    where session_id  = p_session_id
      and delivery_id is null;
  end if;

  return v_rows > 0;
end;
$$;

revoke all on function claim_session(uuid, uuid) from public, anon;
grant execute on function claim_session(uuid, uuid) to authenticated;

-- -------------------------------------------------------
-- 5. TODAY'S SUPPLIER EARNINGS — caller check + IST
--    Old version had no auth check (any user could read
--    any supplier's revenue) and used UTC dates.
-- -------------------------------------------------------
create or replace function get_today_supplier_earnings(p_supplier_id uuid)
returns numeric language plpgsql stable security definer
set search_path = public as $$
declare
  v_earnings numeric;
  v_today    date;
begin
  if auth.uid() <> p_supplier_id and not is_admin() then
    raise exception 'access denied';
  end if;

  v_today := (now() at time zone 'Asia/Kolkata')::date;

  select coalesce(sum(subtotal), 0) into v_earnings
  from orders
  where supplier_id = p_supplier_id
    and status      = 'delivered'
    and (placed_at at time zone 'Asia/Kolkata')::date = v_today;

  return v_earnings;
end;
$$;

revoke all on function get_today_supplier_earnings(uuid) from public, anon;
grant execute on function get_today_supplier_earnings(uuid) to authenticated;

-- -------------------------------------------------------
-- 5b. RECOMPUTE SESSION TOTAL AFTER PACKING
--     Supplier packing marks items unavailable → the order
--     subtotal and parent session total must reflect what
--     was actually packed so the customer is billed correctly
--     (COD collect amount).
--     SECURITY DEFINER because the supplier cannot (and
--     should not) read sibling sub-orders or update the
--     session row under RLS.
--     Caller must be the supplier who owns p_order_id.
-- -------------------------------------------------------
create or replace function recompute_session_total(p_order_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_supplier     uuid;
  v_session      uuid;
  v_new_subtotal numeric;
  v_orders_total numeric;
  v_fee          numeric;
begin
  select supplier_id, session_id into v_supplier, v_session
  from orders where id = p_order_id;

  if v_supplier is null then
    raise exception 'order not found';
  end if;
  if auth.uid() <> v_supplier and not is_admin() then
    raise exception 'only the supplier can recompute this order';
  end if;

  -- Recompute this order's subtotal from packed (effective) quantities.
  select coalesce(sum(
           case when coalesce(ois.is_available, true)
                then oi.unit_price * coalesce(ois.available_qty, oi.quantity)
                else 0 end), 0)
    into v_new_subtotal
  from order_items oi
  left join order_item_status ois on ois.order_item_id = oi.id
  where oi.order_id = p_order_id;

  update orders
  set subtotal = v_new_subtotal, total = v_new_subtotal
  where id = p_order_id;

  if v_session is null then return; end if;

  -- Recompute session total = sum of live sub-orders + delivery fee.
  select coalesce(sum(subtotal), 0) into v_orders_total
  from orders
  where session_id = v_session
    and status not in ('cancelled', 'returned');

  select coalesce(delivery_fee, 0) into v_fee
  from order_sessions where id = v_session;

  update order_sessions
  set total = v_orders_total + coalesce(v_fee, 0)
  where id = v_session;
end;
$$;

revoke all on function recompute_session_total(uuid) from public, anon;
grant execute on function recompute_session_total(uuid) to authenticated;

-- -------------------------------------------------------
-- 6. SESSION UPDATE POLICY — add WITH CHECK
--    Old policy had no WITH CHECK, so a customer/agent
--    passing the USING filter could rewrite any column,
--    including forcing status='delivered' (bypassing
--    agent-earnings crediting) or reassigning delivery_id.
-- -------------------------------------------------------
drop policy if exists "session_update_agent" on order_sessions;
create policy "session_update_agent" on order_sessions for update
  using (
    auth.uid() = delivery_id
    or auth.uid() = customer_id
    or is_admin()
  )
  with check (
    -- Admin can do anything.
    is_admin()
    -- Customer may cancel their own session but cannot mark it
    -- delivered or advance it through the delivery lifecycle.
    or (
      auth.uid() = customer_id
      and status in ('waiting_suppliers', 'cancelled')
    )
    -- Agent may update out_for_delivery sessions but cannot mark
    -- them delivered directly (use complete_session_delivery RPC).
    or (
      auth.uid() = delivery_id
      and status in ('out_for_delivery')
    )
  );
