-- Patch: Extend members schema and RLS to support user self-enrollment (whitelist)
-- Run this after supabase.sql has been applied

-- 1) Schema: add email and status to members, with constraints
alter table public.members
  add column if not exists email text,
  add column if not exists status text not null default 'pending' check (status in ('pending','active','revoked','blocked'));

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

-- 4) Optional: backfill existing users (run manually if needed)
-- insert into public.members (user_id, email, role, status)
-- select id as user_id, email, 'user' as role, 'pending' as status from auth.users
-- on conflict (user_id) do update set email = excluded.email;