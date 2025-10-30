-- Taixuan 自写策略 Patch：允许普通登录用户写自己的数据（students 与 app_kv_store）
-- 复制到 Supabase 控制台 SQL 编辑器执行；可重复执行（使用 IF/DO $$ 保护）

-- 1) 兼容所需扩展
create extension if not exists pgcrypto;

-- 2) students: 为自写添加归属列与 RLS 策略（不改变现有管理员策略）
alter table if exists public.students add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.students enable row level security;
alter table public.students force row level security;

DO $$ BEGIN
  CREATE POLICY students_user_insert ON public.students
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY students_user_update ON public.students
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY students_user_delete ON public.students
    FOR DELETE TO authenticated
    USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3) app_kv_store: 自写策略（保留管理员策略）；触发器自动记录 updated_by
alter table if exists public.app_kv_store add column if not exists updated_by uuid;
alter table public.app_kv_store enable row level security;
alter table public.app_kv_store force row level security;

create or replace function public.kv_set_updated_by()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if (auth.uid() is not null) then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists kv_before_write on public.app_kv_store;
create trigger kv_before_write
before insert or update on public.app_kv_store
for each row execute function public.kv_set_updated_by();

DO $$ BEGIN
  CREATE POLICY kv_user_insert_self ON public.app_kv_store
    FOR INSERT TO authenticated
    WITH CHECK (updated_by = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY kv_user_update_self ON public.app_kv_store
    FOR UPDATE TO authenticated
    USING (updated_by = auth.uid())
    WITH CHECK (updated_by = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY kv_user_delete_self ON public.app_kv_store
    FOR DELETE TO authenticated
    USING (updated_by = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 4) 可选：members（管理员/审批用）。若不存在，可创建基础表并开启 RLS
create table if not exists public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','user')),
  email text,
  status text check (status in ('active','pending','banned')) default 'active',
  created_at timestamptz not null default now()
);
alter table public.members enable row level security;
alter table public.members force row level security;

DO $$ BEGIN
  CREATE POLICY members_select_self_or_admin ON public.members
    FOR SELECT TO authenticated
    USING (
      user_id = auth.uid()
      OR EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY members_admin_write ON public.members
    FOR INSERT TO authenticated
    WITH CHECK (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY members_admin_update ON public.members
    FOR UPDATE TO authenticated
    USING (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    )
    WITH CHECK (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY members_admin_delete ON public.members
    FOR DELETE TO authenticated
    USING (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 5) 验证建议：
-- select id, email, user_id from public.students order by created_at desc limit 5;
-- select key, updated_by, updated_at from public.app_kv_store order by updated_at desc limit 5;