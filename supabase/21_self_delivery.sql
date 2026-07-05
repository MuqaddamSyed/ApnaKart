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
