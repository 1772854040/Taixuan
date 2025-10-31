-- Diagnostics log table for health checks and RPC actions
begin;

create table if not exists public.app_diagnostics_log (
  id bigserial primary key,
  ts timestamptz not null default now(),
  user_id uuid,
  email text,
  action text not null,
  status text not null,
  message text,
  meta jsonb
);

-- Indexes for faster audit queries
create index if not exists idx_app_diag_ts on public.app_diagnostics_log (ts desc);
create index if not exists idx_app_diag_action on public.app_diagnostics_log (action);
create index if not exists idx_app_diag_user on public.app_diagnostics_log (user_id);

-- RLS: authenticated can insert; admin can select; self can select own logs
alter table if exists public.app_diagnostics_log enable row level security;

drop policy if exists app_diag_insert_self on public.app_diagnostics_log;
create policy app_diag_insert_self on public.app_diagnostics_log
  for insert to authenticated
  with check ( user_id is null or user_id = auth.uid() );

drop policy if exists app_diag_select_admin_or_self on public.app_diagnostics_log;
create policy app_diag_select_admin_or_self on public.app_diagnostics_log
  for select to authenticated
  using (
    (user_id = auth.uid())
    or exists(select 1 from public.members m where m.user_id = auth.uid() and m.role = 'admin')
  );

commit;