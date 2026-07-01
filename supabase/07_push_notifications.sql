-- ============================================================
-- FCM device token storage.
-- Run before enabling push notification sends.
-- ============================================================

create table if not exists device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  token text not null unique,
  platform text default 'android',
  app_role text check (app_role in ('customer','supplier','delivery','admin')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table device_tokens enable row level security;

drop policy if exists device_tokens_owner on device_tokens;
create policy device_tokens_owner on device_tokens
  for all using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());
