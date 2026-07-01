-- ============================================================
-- Order lifecycle v2: new statuses, agent name, OTP-free completion.
-- Run once in the Supabase SQL editor (after 01–11).
-- ============================================================

-- 1. Allow the new statuses: 'arrived' (agent reached customer) and
--    'returned' (customer refused at the door).
alter table orders drop constraint if exists orders_status_check;
alter table orders add constraint orders_status_check check (status in (
  'placed','confirmed','preparing','picked_up',
  'on_the_way','arrived','delivered','returned','cancelled'
));

-- 2. Delivery agent name (shown in the agent + admin apps).
alter table delivery_agents add column if not exists name text;

-- 3. OTP-free delivery completion. Marks the order delivered (the existing
--    trg_stamp_delivered trigger stamps delivered_at + payment_status='paid')
--    and credits the assigned agent's earnings + deliveries — atomically.
--    SECURITY DEFINER so it can update the agent row; guarded to the
--    order's own agent (or an admin).
create or replace function complete_delivery(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent uuid;
  v_fee numeric;
begin
  select delivery_id, delivery_fee into v_agent, v_fee
  from orders where id = p_order_id;

  if v_agent is null then
    raise exception 'order has no assigned delivery agent';
  end if;
  if auth.uid() <> v_agent and not is_admin() then
    raise exception 'only the assigned agent can complete this delivery';
  end if;

  update orders set status = 'delivered' where id = p_order_id;

  update delivery_agents
    set earnings_today = coalesce(earnings_today, 0) + coalesce(v_fee, 0),
        total_deliveries = coalesce(total_deliveries, 0) + 1
  where id = v_agent;
end;
$$;

revoke all on function complete_delivery(uuid) from public, anon;
grant execute on function complete_delivery(uuid) to authenticated;
