-- ============================================================
-- V2 fix: delivery pool visibility + sub-order assignment.
-- Run once after 13_v2_multi_supplier.sql.
--
-- Two problems this fixes:
--   1. session_select RLS never let a verified agent SEE unclaimed
--      'all_confirmed' sessions, so the pool was always empty for agents.
--   2. claim_session assigned the agent to the SESSION only, not the
--      sub-orders — so the agent's later reads/updates on those orders
--      failed RLS (delivery_id stayed null). Now it stamps every sub-order.
-- ============================================================

-- 1. Let verified agents view the unclaimed, all-confirmed session pool.
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
    or (
      status = 'all_confirmed'
      and delivery_id is null
      and exists (
        select 1 from delivery_agents a
        where a.id = auth.uid() and a.is_verified = true
      )
    )
  );

-- 2. Claiming a session also assigns the agent to every sub-order, so all
--    subsequent order reads/updates pass RLS via delivery_id = auth.uid().
create or replace function claim_session(p_session_id uuid, p_agent_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
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

  if v_rows > 0 then
    update orders
    set delivery_id = p_agent_id
    where session_id = p_session_id
      and delivery_id is null;
  end if;

  return v_rows > 0;
end;
$$;

revoke all on function claim_session(uuid, uuid) from public, anon;
grant execute on function claim_session(uuid, uuid) to authenticated;
