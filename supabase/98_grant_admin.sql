-- ============================================================
-- GRANT ADMIN ACCESS
-- Makes an existing auth user an admin (is_admin() checks for a
-- public.users row with role = 'admin' matching auth.uid()).
--
-- PREREQUISITE — create the auth account FIRST (the admin app is
-- sign-in only, no in-app signup):
--   Supabase Dashboard → Authentication → Users → "Add user"
--     • Email:    muqaddam257@gmail.com
--     • Password: (choose one — you'll log in with it)
--     • tick "Auto Confirm User"
-- Then run the block below.
--
-- Safe to re-run. If a public.users row already exists for this
-- account (e.g. you signed up as a customer), it just flips role
-- to 'admin'. The phone placeholder is derived from the user id so
-- it never collides with the NOT NULL / UNIQUE phone constraint.
-- ============================================================

insert into public.users (id, phone, email, name, role)
select u.id,
       'admin-' || left(replace(u.id::text, '-', ''), 12),
       u.email,
       'Admin',
       'admin'
from auth.users u
where u.email = 'muqaddam257@gmail.com'
on conflict (id) do update
  set role  = 'admin',
      email = excluded.email;

-- Verify (should show one row with role = admin):
select id, email, role from public.users
where email = 'muqaddam257@gmail.com';
