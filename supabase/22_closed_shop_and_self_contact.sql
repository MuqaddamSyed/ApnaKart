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
