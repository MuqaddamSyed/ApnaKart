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
