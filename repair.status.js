(function(){
  function h(tag, attrs){ const el = document.createElement(tag); if(attrs){ for(const k in attrs){ if(k==='text') el.textContent = attrs[k]; else el.setAttribute(k, attrs[k]); } } return el; }
  function isSupabaseConfigValid(){
    try{
      const u = (window.__SUPABASE__ && window.__SUPABASE__.url) || '';
      const a = (window.__SUPABASE__ && window.__SUPABASE__.anon) || '';
      const okDomain = /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(u) && !/your-project\.supabase\.co/i.test(u);
      return !!(window.supabase && okDomain && a && a.length > 20);
    }catch(e){ return false; }
  }
  async function getClient(){
    if (!isSupabaseConfigValid()) throw new Error('Supabase 未就绪');
    if (!window.supabaseClient) window.supabaseClient = window.supabase.createClient(window.__SUPABASE__.url, window.__SUPABASE__.anon);
    return window.supabaseClient;
  }
  async function ensureLogin(){
    const c = await getClient();
    let { data: sess } = await c.auth.getSession();
    let user = sess && sess.session && sess.session.user || null;
    if (!user){
      const email = 'diagnostic+' + Date.now() + '@example.com';
      const password = 'Diag_' + Math.random().toString(36).slice(2) + 'Aa1!';
      try { await c.auth.signUp({ email, password }); } catch(_){ }
      const si = await c.auth.signInWithPassword({ email, password });
      if (si && si.error) throw new Error(si.error.message);
      ({ data: sess } = await c.auth.getSession());
      user = sess && sess.session && sess.session.user || null;
    }
    return { c, user };
  }
  async function refreshIfExpired(c){
    try { await c.auth.refreshSession(); } catch(_){}
    return c;
  }
  async function testKVUpdatedBy(){
    try{
      let { c, user } = await ensureLogin();
      const key = 'diag_updated_by_' + Date.now();
      let { error: e1 } = await c.from('app_kv_store').upsert({ key, value: { ts: Date.now() }, updated_at: new Date().toISOString() }, { onConflict: 'key' });
      if (e1 && /JWT expired/i.test(e1.message)){
        await refreshIfExpired(c);
        ({ error: e1 } = await c.from('app_kv_store').upsert({ key, value: { ts: Date.now() }, updated_at: new Date().toISOString() }, { onConflict: 'key' }));
      }
      if (e1){
        // 尝试重新登录一个新会话后重试
        ({ c, user } = await ensureLogin());
        ({ error: e1 } = await c.from('app_kv_store').upsert({ key, value: { ts: Date.now() }, updated_at: new Date().toISOString() }, { onConflict: 'key' }));
      }
      if (e1) return { ok:false, msg:'写入失败：' + e1.message };
      const { data, error: e2 } = await c.from('app_kv_store').select('updated_by').eq('key', key).limit(1).maybeSingle();
      if (e2) return { ok:false, msg:'读取失败：' + e2.message };
      const ok = !!(data && data.updated_by && data.updated_by === user.id);
      return { ok, msg: ok ? ('updated_by=' + data.updated_by) : ('updated_by 不匹配或为空') };
    } catch(e){ return { ok:false, msg:e && e.message ? e.message : String(e) }; }
  }
  async function testStudentOwnership(){
    try{
      let { c, user } = await ensureLogin();
      const email = (user.email || '').trim();
      // 尝试插入/更新以适配不同 schema
      const payloadFull = { name:'Diag Student', email, group:'DiagGroup', joinDate:new Date().toISOString(), progress:1, studyTime:1, courses:[], user_id:user.id };
      let { error: e1 } = await c.from('students').upsert(payloadFull);
      if (e1 && /JWT expired/i.test(e1.message)){
        await refreshIfExpired(c);
        ({ error: e1 } = await c.from('students').upsert(payloadFull));
      }
      if (e1){
        // 最小字段集兜底
        const payloadMin = { email, user_id: user.id };
        ({ error: e1 } = await c.from('students').upsert(payloadMin));
        if (e1 && /JWT expired/i.test(e1.message)){
          await refreshIfExpired(c);
          ({ error: e1 } = await c.from('students').upsert(payloadMin));
        }
        // 若提示 id 非空约束，补一个 bigint 兼容值
        if (e1 && /not null|null value in column\s+"id"/i.test(e1.message)){
          const payloadWithId = { ...payloadMin, id: Date.now() };
          ({ error: e1 } = await c.from('students').upsert(payloadWithId));
        }
      }
      // 若 upsert 可能因唯一键冲突导致更新被 RLS 拦截，调用 RPC 以安全绑定/插入
      try{ await c.rpc('link_my_student_record'); }catch(e){ if (/JWT expired/i.test(e.message)) { await refreshIfExpired(c); try{ await c.rpc('link_my_student_record'); }catch(_){} } }
      try{ await c.rpc('ensure_my_student_row'); }catch(e){ if (/JWT expired/i.test(e.message)) { await refreshIfExpired(c); try{ await c.rpc('ensure_my_student_row'); }catch(_){} } }
    
      if (e1) return { ok:false, msg:'写入失败：' + e1.message };
      // 先按 user_id 查本人记录（maybeSingle 简化判断）
      let r1 = await c.from('students').select('user_id').eq('user_id', user.id).limit(1).maybeSingle();
      if (r1 && r1.error && /JWT expired/i.test(r1.error.message)){ await refreshIfExpired(c); r1 = await c.from('students').select('user_id').eq('user_id', user.id).limit(1).maybeSingle(); }
      let ok = !!(r1 && r1.data && r1.data.user_id);
      if (!ok){
        // 再按邮箱兜底：使用通配提升兼容性，但仅认精确邮箱
        let byMailObj = await c.from('students').select('email,user_id').ilike('email', '%' + email + '%');
        if (byMailObj && byMailObj.error && /JWT expired/i.test(byMailObj.error.message)){ await refreshIfExpired(c); byMailObj = await c.from('students').select('email,user_id').ilike('email', '%' + email + '%'); }
        const byMail = Array.isArray(byMailObj && byMailObj.data) ? byMailObj.data : [];
        const exactRows = byMail.filter(r => (r.email||'').toLowerCase() === email.toLowerCase());
        const someHasUid = exactRows.some(r => r.user_id && String(r.user_id).length > 0);
        if (exactRows.length > 0 && !someHasUid){
          // 再尝试绑定一次并复查
          try{ await c.rpc('link_my_student_record'); await c.rpc('ensure_my_student_row'); }catch(_){ /* ignore */ }
          byMailObj = await c.from('students').select('email,user_id').ilike('email', '%' + email + '%');
        }
        ok = someHasUid || !!(r1 && r1.data && r1.data.user_id);
        if (ok){ return { ok:true, msg: '读取到本人记录（按邮箱或 user_id）' }; }
        if (exactRows.length > 0){ return { ok:false, msg: '命中邮箱但未绑定 user_id（需执行策略或RPC）' }; }
      }
    
      return { ok, msg: ok ? ('读取到本人记录') : ('无本人记录（uid=' + user.id + ', email=' + email + ')') };
    } catch(e){ return { ok:false, msg:e && e.message ? e.message : String(e) }; }
  }
  async function testAnonKVRead(){
    if (!isSupabaseConfigValid()) return { ok:false, msg:'配置未就绪' };
    // 使用匿名请求直接读取，不全局登出，避免影响当前会话
    try{
      const url = (window.__SUPABASE__ && window.__SUPABASE__.url || '').replace(/\/$/, '');
      const anon = (window.__SUPABASE__ && window.__SUPABASE__.anon) || '';
      const p = new URLSearchParams();
      p.append('select','key');
      p.append('key','eq.taixuanVipCodes');
      p.append('limit','1');
      const r = await fetch(url + '/rest/v1/app_kv_store?' + p.toString(), { headers: { 'apikey': anon, 'Content-Type':'application/json' } });
      const j = await (async ()=>{ try{ return await r.json(); }catch(_){ return null; } })();
      if (!r.ok) return { ok:false, msg: (j && j.message) || r.statusText || '读取失败' };
      return { ok:true, msg:'可读取' };
    }catch(e){ return { ok:false, msg: e && e.message ? e.message : String(e) }; }
  }
  function setStatus(el, res){ el.textContent = (res.ok ? '通过 ✅ ' : '失败 ❌ ') + (res.msg || ''); el.className = res.ok ? 'ok' : 'err'; }
  async function runDiagnostics(){
    const elemAnon = document.getElementById('diag_anon');
    const elemUpd = document.getElementById('diag_upd');
    const elemStu = document.getElementById('diag_stu');
    elemAnon.textContent = '检测中…'; elemUpd.textContent = '检测中…'; elemStu.textContent = '检测中…';
    try { setStatus(elemAnon, await testAnonKVRead()); } catch(e){ setStatus(elemAnon, { ok:false, msg:String(e) }); }
    try { setStatus(elemUpd, await testKVUpdatedBy()); } catch(e){ setStatus(elemUpd, { ok:false, msg:String(e) }); }
    try { setStatus(elemStu, await testStudentOwnership()); } catch(e){ setStatus(elemStu, { ok:false, msg:String(e) }); }
  }
  function injectCard(){
    // 若页面已存在自测元素，则不再注入，避免重复
    if (document.getElementById('diag_anon') || document.getElementById('diag_upd') || document.getElementById('diag_stu')) {
      return;
    }
    const card = h('div', { class:'card' });
    const title = h('div', { class:'title', text:'快速自测（页面内验证）' });
    const p = h('div', { class:'kv' }); p.innerHTML = '验证三项：匿名 KV 读取、KV 写回 updated_by、学员归属 user_id。';
    const ul = h('ul'); ul.style.listStyle = 'none'; ul.style.paddingLeft = '0';
    const li1 = h('li'); li1.innerHTML = '匿名 KV 读取：<span id="diag_anon" class="mono">待测</span>';
    const li2 = h('li'); li2.innerHTML = 'KV 写回(updated_by)：<span id="diag_upd" class="mono">待测</span>';
    const li3 = h('li'); li3.innerHTML = '学员归属(user_id)：<span id="diag_stu" class="mono">待测</span>';
    ul.appendChild(li1); ul.appendChild(li2); ul.appendChild(li3);
    const row = h('div', { class:'row' });
    const btn = h('button'); btn.textContent = '运行自测'; btn.addEventListener('click', runDiagnostics);
    row.appendChild(btn);
    card.appendChild(title); card.appendChild(p); card.appendChild(ul); card.appendChild(row);
    document.body.appendChild(card);
  }
  // 将关键诊断函数导出为全局，便于页面上的按钮调用
  try { window.runDiagnostics = runDiagnostics; } catch(_) {}
  try { window.SB_isConfigValid = isSupabaseConfigValid; } catch(_) {}
  try { window.SB_getClient = getClient; } catch(_) {}
  try { window.SB_ensureLogin = ensureLogin; } catch(_) {}

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', injectCard);
  else injectCard();
})();