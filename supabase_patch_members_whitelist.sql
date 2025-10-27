-- Patch: Extend members schema and RLS to support user self-enrollment (whitelist)
-- Run this after supabase.sql has been applied

-- 1) Schema: add email and status to members, with constraints
alter table public.members
  add column if not exists email text,
  add column if not exists status text not null default 'pending' check (status in ('pending','active','revoked','blocked')),
  add column if not exists vip_plan text check (vip_plan in ('monthly','yearly')),
  add column if not exists vip_expire_at bigint;

-- Unique constraint on user_id (ensure 1:1 mapping to auth.users)
do $$ begin
  alter table public.members add constraint members_user_id_unique unique (user_id);
exception when duplicate_object then null; end $$;

-- Unique constraint on email (optional but recommended)
do $$ begin
  alter table public.members add constraint members_email_unique unique (email);
exception when duplicate_object then null; end $$;

-- 2) Index for fast lookups by email and status
create index if not exists members_email_idx on public.members(email);
create index if not exists members_status_idx on public.members(status);

-- 3) RLS: allow authenticated users to create/update their own member row, but not escalate role
-- Insert self with forced role='user'
do $$ begin
  create policy members_insert_self on public.members
    for insert to authenticated
    with check (
      user_id = auth.uid() and role = 'user'
    );
exception when duplicate_object then null; end $$;

-- Update self (email/status only), keep role='user'
do $$ begin
  create policy members_update_self on public.members
    for update to authenticated
    using (
      user_id = auth.uid()
    )
    with check (
      user_id = auth.uid() and role = 'user' and status in ('pending','active','revoked','blocked')
    );
exception when duplicate_object then null; end $$;

-- Note: admin policies from supabase.sql remain, enabling full management by admins.

-- 4) Trigger: auto-create members row when a new auth.users record is inserted
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.members(user_id, email, role, status)
  values (new.id, new.email, 'user', 'pending')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 5) Backfill existing users missing a members row (one-time fix)
insert into public.members(user_id, email, role, status)
select u.id, u.email, 'user', 'pending'
from auth.users u
where not exists (
  select 1 from public.members m where m.user_id = u.id
)
on conflict (user_id) do nothing;