-- ============================================================
-- CONSOLIDATED MIGRATIONS 17–22  (ApnaKart / QuickKart)
-- Run ONCE in the Supabase SQL editor, AFTER 13–16 are applied.
-- Fully idempotent + ordered — safe to re-run any time.
-- Later sections intentionally redefine earlier functions
-- (get_agent_cod_total, get_session_contacts) to their final form.
-- ============================================================

-- ############################################################
-- ## 17_flow_robustness.sql
-- ############################################################

-- ============================================================
-- FLOW ROBUSTNESS + AUDIT + SETTLEMENT
-- Run ONCE in the Supabase SQL editor AFTER migrations 13–16.
-- Safe to re-run (idempotent).
--
-- Adds:
--   1. OTP-at-door handoff (secure agent-driven completion).
--   2. Session/agent timeouts (auto-cancel stale sessions).
--   3. order_events audit trail (debuggable flows).
--   4. v_settlements (COD cash / supplier payable / agent fee).
-- ============================================================

-- -------------------------------------------------------
-- 1. OTP-AT-DOOR HANDOFF
--    The customer's old "I received my order" button called
--    complete_session_delivery(), which is AGENT-ONLY, so it
--    always failed. Correct flow: agent marks arrived → a 4-digit
--    code is generated and shown ONLY to the customer → the agent
--    enters that code to complete. The code lives in its own table
--    so it never appears in the agent's realtime session stream.
-- -------------------------------------------------------
create table if not exists session_handoff (
  session_id uuid primary key references order_sessions(id) on delete cascade,
  otp        text not null,
  created_at timestamptz default now()
);

alter table session_handoff enable row level security;

-- Only the owning customer (or admin) may read the code. Agents cannot.
drop policy if exists handoff_customer_select on session_handoff;
create policy handoff_customer_select on session_handoff for select
  using (
    exists (
      select 1 from order_sessions s
      where s.id = session_handoff.session_id
        and (s.customer_id = auth.uid() or is_admin())
    )
  );
-- No client write policies: only the SECURITY DEFINER RPCs below write here.

-- Agent marks arrival: flips sub-orders to 'arrived' and (re)generates
-- the handoff code. Agent-only.
create or replace function mark_session_arrived(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_agent uuid;
begin
  select delivery_id into v_agent from order_sessions where id = p_session_id;
  if v_agent is null then
    raise exception 'session has no assigned delivery agent';
  end if;
  if auth.uid() <> v_agent and not is_admin() then
    raise exception 'only the assigned agent can mark arrival';
  end if;

  update orders set status = 'arrived'
  where session_id = p_session_id
    and status not in ('cancelled', 'delivered', 'returned');

  insert into session_handoff (session_id, otp)
  values (p_session_id, lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict (session_id) do update
    set otp = excluded.otp, created_at = now();
end;
$$;

revoke all on function mark_session_arrived(uuid) from public, anon;
grant execute on function mark_session_arrived(uuid) to authenticated;

-- Agent completes delivery by entering the customer's code.
create or replace function complete_session_delivery(p_session_id uuid, p_otp text)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_agent uuid;
  v_otp   text;
begin
  select delivery_id into v_agent from order_sessions where id = p_session_id;
  if v_agent is null then
    raise exception 'session has no assigned delivery agent';
  end if;
  if auth.uid() <> v_agent and not is_admin() then
    raise exception 'only the assigned agent can complete this delivery';
  end if;

  select otp into v_otp from session_handoff where session_id = p_session_id;
  if v_otp is null or v_otp <> p_otp then
    raise exception 'invalid delivery code';
  end if;

  -- Reuse the existing completion logic (marks delivered, credits agent).
  perform complete_session_delivery(p_session_id);
end;
$$;

revoke all on function complete_session_delivery(uuid, text) from public, anon;
grant execute on function complete_session_delivery(uuid, text) to authenticated;

-- -------------------------------------------------------
-- 2. TIMEOUTS — auto-cancel sessions no supplier ever accepts.
--    A session stuck in 'waiting_suppliers' past the window is
--    cancelled so the customer isn't left hanging. Unclaimed
--    'all_confirmed' sessions are left for admin visibility.
-- -------------------------------------------------------
create or replace function expire_stale_sessions(p_minutes int default 15)
returns int language plpgsql security definer
set search_path = public as $$
declare
  v_count int;
begin
  update order_sessions
  set status = 'cancelled'
  where status = 'waiting_suppliers'
    and placed_at < now() - make_interval(mins => p_minutes);
  get diagnostics v_count = row_count;

  update orders set status = 'cancelled'
  where session_id in (select id from order_sessions where status = 'cancelled')
    and status not in ('delivered', 'returned', 'cancelled');

  return v_count;
end;
$$;

revoke all on function expire_stale_sessions(int) from public, anon;
grant execute on function expire_stale_sessions(int) to authenticated;

-- Schedule every 5 min if pg_cron is available (enable it under
-- Database → Extensions). Harmless if the extension is absent.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('expire-stale-sessions')
      where exists (select 1 from cron.job where jobname = 'expire-stale-sessions');
    perform cron.schedule('expire-stale-sessions', '*/5 * * * *',
                          'select expire_stale_sessions(15);');
  end if;
end;
$$;

-- -------------------------------------------------------
-- 3. ORDER EVENTS — append-only status history for debugging
--    and analytics. Every sub-order status change is logged.
-- -------------------------------------------------------
create table if not exists order_events (
  id         bigint generated always as identity primary key,
  order_id   uuid references orders(id) on delete cascade,
  session_id uuid,
  from_status text,
  to_status   text,
  actor       uuid,
  at          timestamptz default now()
);
create index if not exists idx_order_events_order   on order_events(order_id);
create index if not exists idx_order_events_session on order_events(session_id);

create or replace function log_order_event()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into order_events(order_id, session_id, from_status, to_status, actor)
    values (new.id, new.session_id, null, new.status, auth.uid());
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into order_events(order_id, session_id, from_status, to_status, actor)
    values (new.id, new.session_id, old.status, new.status, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_order_event on orders;
create trigger trg_log_order_event
  after insert or update of status on orders
  for each row execute function log_order_event();

alter table order_events enable row level security;
drop policy if exists order_events_read on order_events;
create policy order_events_read on order_events for select
  using (
    is_admin()
    or exists (
      select 1 from orders o
      where o.id = order_events.order_id
        and (o.customer_id = auth.uid()
          or o.supplier_id = auth.uid()
          or o.delivery_id = auth.uid())
    )
  );

-- -------------------------------------------------------
-- 4. SETTLEMENT — COD money tracking per delivered session:
--    cash the agent collects, what each supplier is owed, and
--    the agent's delivery fee.
-- -------------------------------------------------------
create or replace view v_settlements
with (security_invoker = true) as
select
  s.id            as session_id,
  s.display_id    as order_no,
  s.status,
  s.delivered_at,
  s.delivery_id   as agent_id,
  agu.name        as agent_name,
  s.total         as cash_collected,
  s.delivery_fee  as agent_fee,
  coalesce((
    select sum(o.subtotal) from orders o
    where o.session_id = s.id and o.status = 'delivered'
  ), 0)           as supplier_payable
from order_sessions s
left join users agu on agu.id = s.delivery_id
where s.status = 'delivered';

grant select on v_settlements to authenticated;

-- ------------------------------------------------------------
-- Verify:
--   select mark_session_arrived('<session-uuid>');   -- as the agent
--   select * from session_handoff;                   -- as the customer
--   select expire_stale_sessions(15);
--   select * from order_events order by at desc limit 20;
--   select * from v_settlements order by delivered_at desc;
-- ------------------------------------------------------------

-- ############################################################
-- ## 18_agent_cod.sql
-- ############################################################

-- ============================================================
-- AGENT COD TOTAL
-- Run ONCE in the Supabase SQL editor (after 13–17). Idempotent.
--
-- Total cash a delivery agent has collected across every order they
-- delivered (COD). Caller-checked: an agent can only read their own
-- number; admin can read anyone's.
-- ============================================================
create or replace function get_agent_cod_total(p_agent_id uuid)
returns numeric language plpgsql stable security definer
set search_path = public as $$
declare
  v_total numeric;
begin
  if auth.uid() <> p_agent_id and not is_admin() then
    raise exception 'access denied';
  end if;

  select coalesce(sum(total), 0) into v_total
  from order_sessions
  where delivery_id = p_agent_id
    and status = 'delivered';

  return v_total;
end;
$$;

revoke all on function get_agent_cod_total(uuid) from public, anon;
grant execute on function get_agent_cod_total(uuid) to authenticated;

-- ############################################################
-- ## 19_session_contacts.sql
-- ############################################################

-- ============================================================
-- SESSION CONTACTS (for the delivery agent)
-- Run ONCE in the Supabase SQL editor (after 13–18). Idempotent.
--
-- The users table RLS hides other people's phone numbers, so a delivery
-- agent can't read supplier/customer contacts via a normal join. This
-- SECURITY DEFINER RPC returns them with the right privacy rules:
--   • supplier phones  -> any VERIFIED agent (so they can call for pickup),
--                         whether the order is still in the pool or assigned.
--   • customer phone   -> ONLY the agent assigned to the session.
--
-- Returns: { "suppliers": [{supplier_id, shop_name, address, phone}, ...],
--            "customer":  {name, phone}  | null }
-- ============================================================
create or replace function get_session_contacts(p_session_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_delivery uuid;
  v_status   text;
  v_customer uuid;
  v_is_agent boolean;
  v_suppliers jsonb;
  v_customer_json jsonb;
begin
  select delivery_id, status, customer_id
    into v_delivery, v_status, v_customer
  from order_sessions where id = p_session_id;

  if v_customer is null then
    raise exception 'session not found';
  end if;

  select exists (
    select 1 from delivery_agents a
    where a.id = auth.uid() and a.is_verified = true
  ) into v_is_agent;

  -- Must be a verified agent who is either assigned to this session or
  -- looking at it in the open pool.
  if not (
    is_admin()
    or (v_is_agent and (
         auth.uid() = v_delivery
         or (v_status = 'all_confirmed' and v_delivery is null)
       ))
  ) then
    raise exception 'access denied';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'supplier_id', o.supplier_id,
           'shop_name',   s.shop_name,
           'address',     s.address,
           'phone',       u.phone
         )), '[]'::jsonb)
    into v_suppliers
  from orders o
  join suppliers s on s.id = o.supplier_id
  left join users u on u.id = o.supplier_id
  where o.session_id = p_session_id;

  -- Customer contact only for the assigned agent (or admin).
  if auth.uid() = v_delivery or is_admin() then
    select jsonb_build_object('name', u.name, 'phone', u.phone)
      into v_customer_json
    from users u where u.id = v_customer;
  else
    v_customer_json := null;
  end if;

  return jsonb_build_object('suppliers', v_suppliers, 'customer', v_customer_json);
end;
$$;

revoke all on function get_session_contacts(uuid) from public, anon;
grant execute on function get_session_contacts(uuid) to authenticated;

-- ------------------------------------------------------------
-- Agent contact for the SUPPLIER of an order, once a delivery agent has
-- claimed it (delivery_id is stamped on the order at claim time). Lets the
-- supplier call the partner to coordinate pickup. Returns {name, phone}
-- or null if no agent is assigned yet. Caller must own the order.
-- ------------------------------------------------------------
create or replace function get_order_agent_contact(p_order_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_supplier uuid;
  v_delivery uuid;
begin
  select supplier_id, delivery_id into v_supplier, v_delivery
  from orders where id = p_order_id;

  if v_supplier is null then
    raise exception 'order not found';
  end if;
  if auth.uid() <> v_supplier and not is_admin() then
    raise exception 'access denied';
  end if;
  if v_delivery is null then
    return null;
  end if;

  return (select jsonb_build_object('name', u.name, 'phone', u.phone)
          from users u where u.id = v_delivery);
end;
$$;

revoke all on function get_order_agent_contact(uuid) from public, anon;
grant execute on function get_order_agent_contact(uuid) to authenticated;

-- ############################################################
-- ## 20_agent_reject_and_cod.sql
-- ############################################################

-- ============================================================
-- AGENT-SIDE REJECT + CORRECTED COD TOTAL
-- Run ONCE in the Supabase SQL editor (after 13–19). Idempotent.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Agent-authorised reject.
--    reject_session_by_customer is customer-only (auth.uid() = customer_id),
--    so the delivery agent's "Rejected by customer" button was failing.
--    This lets the ASSIGNED agent cancel the session + return its orders.
-- ------------------------------------------------------------
create or replace function reject_session_by_agent(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_agent uuid;
begin
  select delivery_id into v_agent from order_sessions where id = p_session_id;
  if v_agent is null then
    raise exception 'session has no assigned delivery agent';
  end if;
  if auth.uid() <> v_agent and not is_admin() then
    raise exception 'only the assigned agent can reject this delivery';
  end if;

  update order_sessions set status = 'cancelled' where id = p_session_id;
  update orders set status = 'returned'
  where session_id = p_session_id
    and status not in ('cancelled', 'delivered', 'returned');
end;
$$;

revoke all on function reject_session_by_agent(uuid) from public, anon;
grant execute on function reject_session_by_agent(uuid) to authenticated;

-- ------------------------------------------------------------
-- 2. COD total the agent must remit = value of all delivered orders MINUS
--    his own delivery fee per delivery. (He collects the full order value
--    in cash and keeps the delivery fee; this is what he owes.)
-- ------------------------------------------------------------
create or replace function get_agent_cod_total(p_agent_id uuid)
returns numeric language plpgsql stable security definer
set search_path = public as $$
declare
  v_total numeric;
begin
  if auth.uid() <> p_agent_id and not is_admin() then
    raise exception 'access denied';
  end if;

  select coalesce(sum(total - coalesce(delivery_fee, 0)), 0) into v_total
  from order_sessions
  where delivery_id = p_agent_id
    and status = 'delivered';

  return v_total;
end;
$$;

revoke all on function get_agent_cod_total(uuid) from public, anon;
grant execute on function get_agent_cod_total(uuid) to authenticated;

-- ############################################################
-- ## 21_self_delivery.sql
-- ############################################################

-- ============================================================
-- SUPPLIER SELF-DELIVERY
-- Run ONCE in the Supabase SQL editor (after 13–20). Idempotent.
--
-- A shopkeeper can deliver a SINGLE-shop order themselves and keep the
-- delivery fee. Such a session skips the agent pool entirely.
-- Reuses the existing OTP handoff + completion + reject machinery by
-- setting the session's delivery_id to the supplier's user id.
-- ============================================================

alter table order_sessions
  add column if not exists delivery_mode text not null default 'agent'
  check (delivery_mode in ('agent', 'self'));

-- ------------------------------------------------------------
-- Accept an order AND self-deliver it. Single-shop sessions only.
-- Confirms the order and routes the session straight to the supplier
-- (delivery_id = supplier), out for delivery, never touching the pool.
-- ------------------------------------------------------------
create or replace function accept_and_self_deliver(p_order_id uuid)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_supplier uuid;
  v_session  uuid;
  v_count    int;
begin
  select supplier_id, session_id into v_supplier, v_session
  from orders where id = p_order_id;

  if v_supplier is null then
    raise exception 'order not found';
  end if;
  if auth.uid() <> v_supplier and not is_admin() then
    raise exception 'only the supplier can accept this order';
  end if;
  if v_session is null then
    raise exception 'order has no session';
  end if;

  select count(*) into v_count from orders where session_id = v_session;
  if v_count <> 1 then
    raise exception 'self-delivery is only available for single-shop orders';
  end if;

  update orders set status = 'confirmed' where id = p_order_id;

  update order_sessions
  set delivery_mode = 'self',
      delivery_id   = v_supplier,
      status        = 'out_for_delivery'
  where id = v_session;
end;
$$;

revoke all on function accept_and_self_deliver(uuid) from public, anon;
grant execute on function accept_and_self_deliver(uuid) to authenticated;

-- ------------------------------------------------------------
-- Contacts: allow the ASSIGNED deliverer (an agent OR a self-delivering
-- supplier, both stored as delivery_id) to read supplier + customer
-- contacts. Supersedes the definition in migration 19.
-- ------------------------------------------------------------
create or replace function get_session_contacts(p_session_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_delivery uuid;
  v_status   text;
  v_customer uuid;
  v_is_agent boolean;
  v_suppliers jsonb;
  v_customer_json jsonb;
begin
  select delivery_id, status, customer_id
    into v_delivery, v_status, v_customer
  from order_sessions where id = p_session_id;

  if v_customer is null then
    raise exception 'session not found';
  end if;

  select exists (
    select 1 from delivery_agents a
    where a.id = auth.uid() and a.is_verified = true
  ) into v_is_agent;

  if not (
    is_admin()
    or auth.uid() = v_delivery                              -- assigned deliverer
    or (v_is_agent and v_status = 'all_confirmed' and v_delivery is null) -- pool
  ) then
    raise exception 'access denied';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'supplier_id', o.supplier_id,
           'shop_name',   s.shop_name,
           'address',     s.address,
           'phone',       u.phone
         )), '[]'::jsonb)
    into v_suppliers
  from orders o
  join suppliers s on s.id = o.supplier_id
  left join users u on u.id = o.supplier_id
  where o.session_id = p_session_id;

  if auth.uid() = v_delivery or is_admin() then
    select jsonb_build_object('name', u.name, 'phone', u.phone, 'address',
             (select delivery_address from order_sessions where id = p_session_id))
      into v_customer_json
    from users u where u.id = v_customer;
  else
    v_customer_json := null;
  end if;

  return jsonb_build_object('suppliers', v_suppliers, 'customer', v_customer_json);
end;
$$;

revoke all on function get_session_contacts(uuid) from public, anon;
grant execute on function get_session_contacts(uuid) to authenticated;

-- ------------------------------------------------------------
-- Supplier's delivery-fee earnings from orders they self-delivered.
-- ------------------------------------------------------------
create or replace function get_supplier_delivery_earnings(p_supplier_id uuid)
returns numeric language plpgsql stable security definer
set search_path = public as $$
declare
  v_total numeric;
begin
  if auth.uid() <> p_supplier_id and not is_admin() then
    raise exception 'access denied';
  end if;

  select coalesce(sum(delivery_fee), 0) into v_total
  from order_sessions
  where delivery_id = p_supplier_id
    and delivery_mode = 'self'
    and status = 'delivered';

  return v_total;
end;
$$;

revoke all on function get_supplier_delivery_earnings(uuid) from public, anon;
grant execute on function get_supplier_delivery_earnings(uuid) to authenticated;

-- ############################################################
-- ## 22_closed_shop_and_self_contact.sql
-- ############################################################

-- ============================================================
-- CLOSED-SHOP CHECKOUT GUARD + CUSTOMER CONTACT FOR SELF-DELIVERY
-- Run ONCE in the Supabase SQL editor (after 13–21). Idempotent.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Airtight guard: no order can be placed for a closed shop, even if
--    the client is bypassed. Blocks INSERT of a 'placed' order whose
--    supplier is currently closed.
-- ------------------------------------------------------------
create or replace function block_order_for_closed_shop()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  v_open boolean;
begin
  if new.status = 'placed' then
    select is_open into v_open from suppliers where id = new.supplier_id;
    if v_open is false then
      raise exception 'This shop is closed and cannot take orders right now';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_closed_shop on orders;
create trigger trg_block_closed_shop
  before insert on orders
  for each row execute function block_order_for_closed_shop();

-- ------------------------------------------------------------
-- 2. For a SELF-DELIVERED order the "delivery partner" is the shop, so the
--    customer needs the shop's contact. Allow the session's customer to read
--    supplier contacts when delivery_mode = 'self'. Supersedes migration 21.
-- ------------------------------------------------------------
create or replace function get_session_contacts(p_session_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_delivery uuid;
  v_status   text;
  v_customer uuid;
  v_mode     text;
  v_is_agent boolean;
  v_suppliers jsonb;
  v_customer_json jsonb;
begin
  select delivery_id, status, customer_id, delivery_mode
    into v_delivery, v_status, v_customer, v_mode
  from order_sessions where id = p_session_id;

  if v_customer is null then
    raise exception 'session not found';
  end if;

  select exists (
    select 1 from delivery_agents a
    where a.id = auth.uid() and a.is_verified = true
  ) into v_is_agent;

  if not (
    is_admin()
    or auth.uid() = v_delivery                                   -- assigned deliverer
    or (v_is_agent and v_status = 'all_confirmed' and v_delivery is null) -- pool
    or (auth.uid() = v_customer and v_mode = 'self')             -- customer of a self-delivered order
  ) then
    raise exception 'access denied';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'supplier_id', o.supplier_id,
           'shop_name',   s.shop_name,
           'address',     s.address,
           'phone',       u.phone
         )), '[]'::jsonb)
    into v_suppliers
  from orders o
  join suppliers s on s.id = o.supplier_id
  left join users u on u.id = o.supplier_id
  where o.session_id = p_session_id;

  if auth.uid() = v_delivery or is_admin() then
    select jsonb_build_object('name', u.name, 'phone', u.phone, 'address',
             (select delivery_address from order_sessions where id = p_session_id))
      into v_customer_json
    from users u where u.id = v_customer;
  else
    v_customer_json := null;
  end if;

  return jsonb_build_object('suppliers', v_suppliers, 'customer', v_customer_json);
end;
$$;

revoke all on function get_session_contacts(uuid) from public, anon;
grant execute on function get_session_contacts(uuid) to authenticated;
