-- Supabase 初始化与 RLS 策略脚本
-- 说明：将本脚本复制到 Supabase 项目控制台的 SQL 编辑器执行
-- 安全：使用 IF NOT EXISTS / DO $$ ... $$ 处理重复部署；不会破坏既有数据

-- 1) 必要扩展
create extension if not exists pgcrypto;

-- 2) 角色映射表：members（用于在 RLS 中识别管理员）
create table if not exists public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','user')),
  created_at timestamptz not null default now()
);

-- 3) 公告表：announcements
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  created_at timestamptz not null default now()
);

-- 4) 留言/消息表：messages
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  reply text,
  reply_time timestamptz,
  reply_by text,
  reply_read boolean not null default false
);

-- 5) 索引（加速未读查询与用户查询）
create index if not exists messages_user_id_idx on public.messages(user_id);
create index if not exists messages_unread_idx on public.messages(user_id, reply_read);

-- 6) 启用并强制 RLS
alter table public.members enable row level security;
alter table public.announcements enable row level security;
alter table public.messages enable row level security;

alter table public.members force row level security;
alter table public.announcements force row level security;
alter table public.messages force row level security;

-- 7) RLS 策略
-- 说明：is_admin 判定依赖 members 表：存在一条当前用户的记录且 role='admin'
-- EXISTS(
--   select 1 from public.members me where me.user_id = auth.uid() and me.role = 'admin'
-- )

-- 7.1 members 策略
-- 已登录用户只能查看自己的记录；管理员可查看所有并可写
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
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY members_admin_update ON public.members
    FOR UPDATE TO authenticated
    USING (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    )
    WITH CHECK (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY members_admin_delete ON public.members
    FOR DELETE TO authenticated
    USING (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 7.2 announcements 策略
-- 公告对所有用户可读（含匿名），仅管理员可写
DO $$ BEGIN
  CREATE POLICY announcements_select_authenticated ON public.announcements
    FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY announcements_select_anon ON public.announcements
    FOR SELECT TO anon
    USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY announcements_admin_insert ON public.announcements
    FOR INSERT TO authenticated
    WITH CHECK (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY announcements_admin_update ON public.announcements
    FOR UPDATE TO authenticated
    USING (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    )
    WITH CHECK (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY announcements_admin_delete ON public.announcements
    FOR DELETE TO authenticated
    USING (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 7.3 messages 策略
-- 用户：只能访问/写自己的消息；管理员：可管理所有消息
DO $$ BEGIN
  CREATE POLICY messages_select_self_or_admin ON public.messages
    FOR SELECT TO authenticated
    USING (
      user_id = auth.uid()
      OR EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY messages_insert_self ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
      user_id = auth.uid()
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY messages_update_self ON public.messages
    FOR UPDATE TO authenticated
    USING (
      user_id = auth.uid()
    )
    WITH CHECK (
      user_id = auth.uid()
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY messages_update_admin ON public.messages
    FOR UPDATE TO authenticated
    USING (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    )
    WITH CHECK (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY messages_delete_admin ON public.messages
    FOR DELETE TO authenticated
    USING (
      EXISTS(
        SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin'
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 8) 管理员赋权示例（执行前请替换 <ADMIN_UUID> 为你的管理员用户ID）
-- 可在 SQL 编辑器单独执行以下语句：
-- INSERT INTO public.members (user_id, role)
-- VALUES ('<ADMIN_UUID>', 'admin')
-- ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

-- 9) 验证示例（在 SQL 编辑器使用 "以用户身份运行" 功能）
-- 作为普通学员：只能看到/更新自己的 messages；可读取 announcements；不可写公告
-- 作为管理员：可读写所有 messages；可增删改公告；可管理 members

-- 10) 注意事项
-- - 若你计划使用 JWT 自定义角色而非 members 表，请改用基于 claims 的策略：
--   current_setting('request.jwt.claims', true)::jsonb ->> 'role' = 'admin'

-- 11) VIP 激活码表：vip_codes
create table if not exists public.vip_codes (
  code text primary key,
  plan text check (plan in ('monthly','yearly')),
  status text not null check (status in ('unused','used')) default 'unused',
  issuedTo text,
  usedBy text,
  createdAt bigint,
  usedAt bigint
);

create index if not exists vip_codes_status_idx on public.vip_codes(status);
create index if not exists vip_codes_created_idx on public.vip_codes(createdAt);

alter table public.vip_codes enable row level security;
alter table public.vip_codes force row level security;

-- RLS 策略：仅管理员可管理/查看；普通登录用户允许更新使用状态（用于自助激活）
DO $$ BEGIN
  CREATE POLICY vip_codes_select_admin ON public.vip_codes
    FOR SELECT TO authenticated
    USING (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY vip_codes_insert_admin ON public.vip_codes
    FOR INSERT TO authenticated
    WITH CHECK (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY vip_codes_delete_admin ON public.vip_codes
    FOR DELETE TO authenticated
    USING (
      EXISTS(SELECT 1 FROM public.members me WHERE me.user_id = auth.uid() AND me.role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY vip_codes_update_authenticated ON public.vip_codes
    FOR UPDATE TO authenticated
    USING (auth.uid() IS NOT NULL)
    WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
-- - 本脚本选择 members 表以获得更可控的角色管理与复用性