// Supabase 项目配置（可直接替换为你的项目 URL/anon）
// 前端只使用 anon（public）键；不要使用 service_role。
(function(){
  var url = 'https://kwjtyvfplkyijxvivdcs.supabase.co';
  var anon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt3anR5dmZwbGt5aWp4dml2ZGNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE0ODQwODAsImV4cCI6MjA3NzA2MDA4MH0.OHxMZpEiFvBENag9UyaNXKoeBMtXIKiFdOfWTL2wX6s';
  if (typeof url === 'string') url = url.trim();
  if (typeof anon === 'string') anon = anon.trim();
  window.__SUPABASE__ = { url: url, anon: anon };
  try {
    window.__SUPABASE_READY__ = !!(url && anon);
    if (window.__SUPABASE_READY__) console.log('[Supabase] config loaded:', url);
  } catch(e) {}
})();