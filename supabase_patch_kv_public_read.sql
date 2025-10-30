-- 开放未登录（anon）读取公共 KV，仅限前缀 taixuanPublic% 与单键 taixuanVipCodes
-- 说明：该策略只授予 SELECT 权限，不包含 INSERT/UPDATE/DELETE
-- 使用方式：在 Supabase 控制台 SQL 编辑器中执行本文件内容

-- 前缀公共读取：taixuanPublic%
DO $$ BEGIN
  CREATE POLICY kv_select_public_prefix ON public.app_kv_store
    FOR SELECT TO anon
    USING (key LIKE 'taixuanPublic%');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 单键公共读取：taixuanVipCodes（如需公开显示该键的内容）
DO $$ BEGIN
  CREATE POLICY kv_select_public_whitelist_vip ON public.app_kv_store
    FOR SELECT TO anon
    USING (key = 'taixuanVipCodes');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 备选：如只开放某个具体键（例如 taixuanPublicClasses），可以改用：
-- DO $$ BEGIN
--   CREATE POLICY kv_select_public_whitelist ON public.app_kv_store
--     FOR SELECT TO anon
--     USING (key = 'taixuanPublicClasses');
-- EXCEPTION WHEN duplicate_object THEN NULL; END $$;