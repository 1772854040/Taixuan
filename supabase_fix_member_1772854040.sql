-- 激活白名单：为指定邮箱创建/更新 members 行为 active
-- 在 Supabase 控制台 -> SQL Editor 中执行本脚本

-- 1) 将该邮箱的用户插入/更新为白名单已激活（role='user', status='active'）
insert into public.members (user_id, email, role, status)
select id as user_id, '1772854040@qq.com' as email, 'user' as role, 'active' as status
from auth.users
where email = '1772854040@qq.com'
on conflict (user_id) do update set
  email = excluded.email,
  role = 'user',
  status = 'active';

-- 2) 验证：应返回 active
select user_id, email, role, status from public.members where email = '1772854040@qq.com';

-- 可选：若需要改回待审批
-- update public.members set status='pending' where email='1772854040@qq.com';