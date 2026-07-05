-- ============================================================
-- CUSTOMER CONTACT FOR THE ORDER'S SUPPLIER
-- Run ONCE in the Supabase SQL editor. Idempotent.
--
-- Lets the supplier of an order see the customer's name, phone and delivery
-- address (the users-table RLS hides phone from a normal join). Used so the
-- shopkeeper can judge the distance before choosing to self-deliver.
-- ============================================================
create or replace function get_order_customer_contact(p_order_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_supplier uuid;
  v_customer uuid;
  v_address  text;
begin
  select o.supplier_id, o.customer_id, o.delivery_address
    into v_supplier, v_customer, v_address
  from orders o where o.id = p_order_id;

  if v_supplier is null then
    raise exception 'order not found';
  end if;
  if auth.uid() <> v_supplier and not is_admin() then
    raise exception 'access denied';
  end if;

  return (select jsonb_build_object(
            'name', u.name,
            'phone', u.phone,
            'address', v_address)
          from users u where u.id = v_customer);
end;
$$;

revoke all on function get_order_customer_contact(uuid) from public, anon;
grant execute on function get_order_customer_contact(uuid) to authenticated;
