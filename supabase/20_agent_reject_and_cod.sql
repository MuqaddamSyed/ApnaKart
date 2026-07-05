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
