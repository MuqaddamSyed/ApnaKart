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
