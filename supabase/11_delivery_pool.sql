-- ============================================================
-- Delivery pool RLS: let VERIFIED delivery agents see and claim
-- unassigned orders that a supplier has accepted (status='confirmed',
-- delivery_id IS NULL). Run once in the Supabase SQL editor.
--
-- Without this, orders_select/update only expose rows where
-- delivery_id = auth.uid(), so agents can never see or accept new work.
-- ============================================================

-- SELECT: parties on the order, admins, OR a verified agent viewing the pool.
drop policy if exists orders_select on orders;
create policy orders_select on orders
  for select using (
    customer_id = auth.uid()
    or supplier_id = auth.uid()
    or delivery_id = auth.uid()
    or is_admin()
    or (
      status = 'confirmed'
      and delivery_id is null
      and exists (
        select 1 from delivery_agents a
        where a.id = auth.uid() and a.is_verified = true
      )
    )
  );

-- UPDATE: existing parties/admin, OR a verified agent claiming a pool order.
-- WITH CHECK stops an agent from writing anyone else into delivery_id.
drop policy if exists orders_update on orders;
create policy orders_update on orders
  for update using (
    customer_id = auth.uid()
    or supplier_id = auth.uid()
    or delivery_id = auth.uid()
    or is_admin()
    or (
      status = 'confirmed'
      and delivery_id is null
      and exists (
        select 1 from delivery_agents a
        where a.id = auth.uid() and a.is_verified = true
      )
    )
  )
  with check (
    customer_id = auth.uid()
    or supplier_id = auth.uid()
    or delivery_id = auth.uid()
    or is_admin()
  );
