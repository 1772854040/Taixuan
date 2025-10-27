-- 通用 KV 存储：按 key 保存整段 JSON（与 localStorage 内容一致）
create table if not exists public.app_kv_store (
  key text primary key,
  value jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- 开启并强制 RLS
alter table public.app_kv_store enable row level security;
alter table public.app_kv_store force row level security;

-- 所有人（含未登录 anon）可读取：用于跨设备拉取数据（如果你希望只登录用户可读，把 'true' 改成 'auth.role() = ''authenticated'''）
create policy "kv_select_public"
on public.app_kv_store
for select
using (true);

-- 仅管理员可写（依赖 members 表中 role='admin'）：
-- updated_by 用 auth.uid() 写入以便审计
create policy "kv_upsert_admin"
on public.app_kv_store
for insert
with check (
  exists (
    select 1
    from public.members m
    where m.user_id = auth.uid() and m.role = 'admin'
  )
);

create policy "kv_update_admin"
on public.app_kv_store
for update
using (
  exists (
    select 1
    from public.members m
    where m.user_id = auth.uid() and m.role = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.members m
    where m.user_id = auth.uid() and m.role = 'admin'
  )
);

create policy "kv_delete_admin"
on public.app_kv_store
for delete
using (
  exists (
    select 1
    from public.members m
    where m.user_id = auth.uid() and m.role = 'admin'
  )
);

-- 更新触发器：自动写 updated_at/updated_by
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