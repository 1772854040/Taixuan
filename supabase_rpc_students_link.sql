-- Supabase RPC functions for linking students.user_id by matching email
-- 1) Admin bulk linking by email
-- 2) Self-service linking for current authenticated user

create or replace function public.link_students_to_auth_by_email_bulk()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  updated integer := 0;
begin
  -- Only admins can run bulk linking
  if not exists (
    select 1 from public.members m
    where m.user_id = auth.uid() and m.role = 'admin'
  ) then
    raise exception 'forbidden: admin only';
  end if;

  update public.students s
  set user_id = u.id
  from auth.users u
  where lower(s.email) = lower(u.email)
    and (s.user_id is distinct from u.id);

  get diagnostics updated = row_count;
  return updated;
end;
$$;

grant execute on function public.link_students_to_auth_by_email_bulk() to authenticated;


create or replace function public.link_my_student_record()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  email text;
  updated integer := 0;
begin
  if uid is null then
    return 0;
  end if;

  select u.email into email
  from auth.users u
  where u.id = uid;

  if email is null then
    return 0;
  end if;

  update public.students s
  set user_id = uid
  where lower(s.email) = lower(email)
    and (s.user_id is distinct from uid);

  get diagnostics updated = row_count;
  return updated;
end;
$$;

grant execute on function public.link_my_student_record() to authenticated;