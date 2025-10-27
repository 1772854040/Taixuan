-- Tables: students and groups for Taixuan admin panel

-- Groups table
create table if not exists public.groups (
  id bigserial primary key,
  name text not null unique,
  manager text,
  createDate text,
  description text,
  level int default 1,
  studentCount int default 0,
  created_at timestamptz default now()
);

-- Students table
create table if not exists public.students (
  id bigint primary key,
  name text,
  email text,
  "group" text,
  joinDate text,
  progress int,
  studyTime int,
  courses jsonb,
  user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz default now()
);

-- Indexes
create index if not exists idx_students_email on public.students(email);
create index if not exists idx_students_group on public.students("group");
create index if not exists idx_groups_name on public.groups(name);

-- RLS policies: admin-only full access
alter table public.students enable row level security;
alter table public.groups enable row level security;

-- Helper predicate: current user is admin (members table must exist)
-- Policies for students
create policy if not exists students_admin_select on public.students
  for select using (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );
create policy if not exists students_admin_insert on public.students
  for insert with check (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );
create policy if not exists students_admin_update on public.students
  for update using (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  ) with check (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );
create policy if not exists students_admin_delete on public.students
  for delete using (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );

-- Policies for groups
create policy if not exists groups_admin_select on public.groups
  for select using (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );
create policy if not exists groups_admin_insert on public.groups
  for insert with check (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );
create policy if not exists groups_admin_update on public.groups
  for update using (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  ) with check (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );
create policy if not exists groups_admin_delete on public.groups
  for delete using (
    exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );

-- Optional: allow a user to view their own student row
create policy if not exists students_user_self_select on public.students
  for select using (user_id = auth.uid());