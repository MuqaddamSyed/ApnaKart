-- ============================================================
-- Supplier + delivery admin approval gate.
-- Run after 01_schema.sql, 02_rls_policies.sql, and 05_email_auth.sql.
-- ============================================================

alter table delivery_agents
  add column if not exists is_verified boolean default false;

create or replace function protect_partner_approval_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- SQL editor/service-role maintenance has no auth.uid(); allow it.
  if auth.uid() is null or is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' and coalesce(new.is_verified, false) = true then
    raise exception 'admin approval is required';
  end if;

  if tg_op = 'UPDATE'
      and coalesce(new.is_verified, false) is distinct from coalesce(old.is_verified, false) then
    raise exception 'only admins can change approval status';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_supplier_approval on suppliers;
create trigger trg_protect_supplier_approval
  before insert or update of is_verified on suppliers
  for each row execute function protect_partner_approval_fields();

drop trigger if exists trg_protect_delivery_approval on delivery_agents;
create trigger trg_protect_delivery_approval
  before insert or update of is_verified on delivery_agents
  for each row execute function protect_partner_approval_fields();

drop policy if exists suppliers_write on suppliers;
create policy suppliers_write on suppliers
  for update using (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  )
  with check (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  );

drop policy if exists products_write on products;
create policy products_write on products
  for all using (
    is_admin()
    or exists (
      select 1 from suppliers s
      where s.id = products.supplier_id
        and s.id = auth.uid()
        and s.is_verified = true
    )
  )
  with check (
    is_admin()
    or exists (
      select 1 from suppliers s
      where s.id = products.supplier_id
        and s.id = auth.uid()
        and s.is_verified = true
    )
  );

drop policy if exists agents_write on delivery_agents;
drop policy if exists agents_insert on delivery_agents;
drop policy if exists agents_update on delivery_agents;

create policy agents_insert on delivery_agents
  for insert with check (
    is_admin()
    or (id = auth.uid() and is_verified = false)
  );

create policy agents_update on delivery_agents
  for update using (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  )
  with check (
    is_admin()
    or (id = auth.uid() and is_verified = true)
  );
