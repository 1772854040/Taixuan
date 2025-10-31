-- Fix students ownership: column, RLS policies, RPCs, grants
-- Safe to run multiple times

begin;

-- 1) Column: ensure user_id exists and references auth.users
alter table if exists public.students
  add column if not exists user_id uuid references auth.users(id) on delete set null;

-- 2) Enable RLS
alter table if exists public.students enable row level security;

-- 3) Read policy: self or admin can read
drop policy if exists students_select_self_or_admin on public.students;
create policy students_select_self_or_admin on public.students
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists(
      select 1 from public.members m
      where m.user_id = auth.uid() and m.role = 'admin'
    )
  );

-- 4) Insert policy: self insert only when user_id = auth.uid()
drop policy if exists students_insert_self on public.students;
create policy students_insert_self on public.students
  for insert to authenticated
  with check ( user_id = auth.uid() );

-- 5) Update policy: allow first-time binding (user_id is null) or self update
drop policy if exists students_update_self on public.students;
create policy students_update_self on public.students
  for update to authenticated
  using (
    user_id is null or user_id = auth.uid()
  )
  with check (
    user_id = auth.uid()
  );

-- 6) RPC: link_my_student_record - bind current user to existing email row (case-insensitive)
drop function if exists public.link_my_student_record();
create or replace function public.link_my_student_record()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  -- derive email from JWT claims (Supabase auth)
  v_email := lower(coalesce(auth.jwt()->>'email', null));
  if v_email is null then
    raise notice 'link_my_student_record: email missing in JWT';
    return;
  end if;

  update public.students s
    set user_id = auth.uid()
  where lower(s.email) = v_email
    and (s.user_id is distinct from auth.uid());
end;
$$;

-- 7) RPC: ensure_my_student_row - ensure there is a row and bind to current user
drop function if exists public.ensure_my_student_row();
create or replace function public.ensure_my_student_row()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_uid uuid := auth.uid();
begin
  v_email := lower(coalesce(auth.jwt()->>'email', null));
  if v_email is null then
    raise notice 'ensure_my_student_row: email missing in JWT';
    return;
  end if;

  -- bind existing row (if any)
  update public.students s
     set user_id = v_uid
   where lower(s.email) = v_email;

  -- insert minimal row if not exists (email, user_id)
  if not exists (
    select 1 from public.students s where lower(s.email) = v_email
  ) then
    insert into public.students(email, user_id)
    values (v_email, v_uid);
  end if;
end;
$$;

-- 8) Grants for RPCs
grant execute on function public.link_my_student_record() to authenticated;
grant execute on function public.ensure_my_student_row() to authenticated;

commit;