-- ============================================================
-- IN-APP ACCOUNT DELETION  (Play/App Store requirement)
-- Run in the Supabase SQL editor. Idempotent.
--
-- A logged-in user calls rpc('delete_my_account'). SECURITY DEFINER lets it
-- remove the auth row (which the anon/authenticated role cannot do directly).
-- Business records (orders/sessions) are ANONYMISED, not deleted, so the
-- supplier's and platform's accounting history stays intact — but every piece
-- of the user's personal data is gone.
--
-- Cascade recap (from 01_schema): deleting public.users removes customers,
-- addresses, device_tokens and notifications automatically. orders and
-- order_sessions reference customers WITHOUT cascade, so we null them first.
-- ============================================================
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Keep the order history but detach it from the person.
  update orders         set customer_id = null where customer_id = uid;
  update order_sessions set customer_id = null where customer_id = uid;

  -- Remove all personal data. customers -> addresses / device_tokens /
  -- notifications fall away via ON DELETE CASCADE.
  delete from public.users where id = uid;

  -- Finally remove the auth identity so the email/phone can be reused.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
