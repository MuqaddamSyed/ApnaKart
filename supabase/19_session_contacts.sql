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
