-- ============================================================
-- QuickKart hardening: hashed delivery OTP + atomic agent
-- earnings increment. Run after 01..03.
-- ============================================================
create extension if not exists pgcrypto;   -- crypt(), gen_salt()

-- Store only a bcrypt hash of the OTP, never plaintext at rest.
alter table orders add column if not exists otp_hash text;

-- Flat payout to the agent per completed delivery (platform-funded,
-- independent of the customer-facing delivery_fee which may be 0).
create or replace function agent_payout() returns numeric as $$
  select 20.00::numeric;
$$ language sql immutable;

-- ------------------------------------------------------------
-- set_order_otp: called by the customer right after placing an
-- order. Hashes + stores the OTP. Only the order's owner may set it.
-- The plaintext is shown to the customer once (client keeps it locally)
-- and is NEVER persisted in plaintext.
-- ------------------------------------------------------------
create or replace function set_order_otp(p_order_id uuid, p_otp text)
returns void as $$
begin
  if not exists (
    select 1 from orders
    where id = p_order_id and customer_id = auth.uid()
  ) then
    raise exception 'not authorised to set OTP for this order';
  end if;

  update orders
    set otp_hash = crypt(p_otp, gen_salt('bf')),
        otp = null                  -- clear any legacy plaintext column
  where id = p_order_id;
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- confirm_delivery_atomic: verifies the OTP against the stored hash
-- and, on match, atomically (single transaction):
--   1. marks the order delivered (delivered_at + COD paid via trigger)
--   2. increments the assigned agent's total_deliveries + earnings_today
-- Returns true on success, false on OTP mismatch. SECURITY DEFINER so
-- it can read otp_hash without exposing it to the caller. The caller
-- (Edge Function, service role) must pass the verified agent id.
-- ------------------------------------------------------------
create or replace function confirm_delivery_atomic(
  p_order_id uuid,
  p_otp text,
  p_agent_id uuid
) returns boolean as $$
declare
  v_hash text;
  v_assigned uuid;
  v_status text;
begin
  select otp_hash, delivery_id, status
    into v_hash, v_assigned, v_status
  from orders where id = p_order_id
  for update;                       -- row lock => atomic

  if v_hash is null then
    raise exception 'order has no OTP set';
  end if;
  if v_assigned is distinct from p_agent_id then
    raise exception 'agent not assigned to this order';
  end if;
  if v_status = 'delivered' then
    return true;                    -- idempotent: already done
  end if;

  -- constant-time-ish compare via crypt: hash(input, stored) = stored
  if crypt(p_otp, v_hash) <> v_hash then
    return false;                   -- OTP mismatch
  end if;

  update orders set status = 'delivered' where id = p_order_id;

  update delivery_agents
    set total_deliveries = total_deliveries + 1,
        earnings_today   = earnings_today + agent_payout()
  where id = p_agent_id;

  return true;
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- reset_daily_earnings: zero earnings_today for all agents. Schedule
-- this at local midnight (pg_cron, or a scheduled Edge Function).
-- ------------------------------------------------------------
create or replace function reset_daily_earnings() returns void as $$
  update delivery_agents set earnings_today = 0;
$$ language sql security definer;

-- Lock down direct execution: only authenticated users may set OTP;
-- confirm_delivery_atomic is intended to be called with the service role
-- (via the Edge Function), so revoke from anon/authenticated.
revoke all on function confirm_delivery_atomic(uuid, text, uuid) from public, anon, authenticated;
grant execute on function set_order_otp(uuid, text) to authenticated;
