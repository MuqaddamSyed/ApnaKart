-- ============================================================
-- Email auth migration. Run after 01_schema.sql for projects
-- that were originally created with phone-only auth. Login uses
-- email OTP, while phone remains required for delivery contact.
-- ============================================================

alter table users
  add column if not exists email text unique;

create table if not exists phone_reuse_flags (
  id uuid primary key default gen_random_uuid(),
  attempted_user_id uuid,
  attempted_email text not null,
  attempted_phone text not null,
  existing_user_id uuid,
  existing_email text,
  existing_phone text,
  existing_name text,
  existing_role text,
  reason text check (reason in ('phone_already_registered','phone_change_attempt')),
  created_at timestamptz default now()
);

alter table phone_reuse_flags enable row level security;

drop policy if exists phone_reuse_flags_admin_read on phone_reuse_flags;
create policy phone_reuse_flags_admin_read on phone_reuse_flags
  for select using (is_admin());

create or replace function register_user_profile(
  p_email text,
  p_phone text,
  p_role text,
  p_name text default null
)
returns users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(p_email));
  v_auth_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_current users%rowtype;
  v_existing users%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if v_email = '' or p_phone is null or trim(p_phone) = '' then
    raise exception 'email and phone are required';
  end if;

  if v_auth_email <> '' and v_auth_email <> v_email then
    raise exception 'email does not match authenticated session';
  end if;

  select * into v_current
  from users
  where id = v_uid;

  select * into v_existing
  from users
  where phone = p_phone and id <> v_uid
  limit 1;

  if found then
    insert into phone_reuse_flags (
      attempted_user_id,
      attempted_email,
      attempted_phone,
      existing_user_id,
      existing_email,
      existing_phone,
      existing_name,
      existing_role,
      reason
    ) values (
      v_uid,
      v_email,
      p_phone,
      v_existing.id,
      v_existing.email,
      v_existing.phone,
      v_existing.name,
      v_existing.role,
      'phone_already_registered'
    );

    raise exception 'This phone number is already registered with another account';
  end if;

  if v_current.id is not null
      and v_current.phone is not null
      and v_current.phone <> p_phone then
    insert into phone_reuse_flags (
      attempted_user_id,
      attempted_email,
      attempted_phone,
      existing_user_id,
      existing_email,
      existing_phone,
      existing_name,
      existing_role,
      reason
    ) values (
      v_uid,
      v_email,
      p_phone,
      v_current.id,
      v_current.email,
      v_current.phone,
      v_current.name,
      v_current.role,
      'phone_change_attempt'
    );

    raise exception 'This account already has a different phone number';
  end if;

  insert into users (id, email, phone, name, role)
  values (v_uid, v_email, p_phone, p_name, p_role)
  on conflict (id) do update set
    email = excluded.email,
    phone = coalesce(users.phone, excluded.phone),
    name = coalesce(excluded.name, users.name),
    role = coalesce(users.role, excluded.role)
  returning * into v_current;

  return v_current;
end;
$$;

revoke all on function register_user_profile(text, text, text, text) from public, anon;
grant execute on function register_user_profile(text, text, text, text) to authenticated;

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
