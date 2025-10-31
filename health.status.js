(function(){
  function setText(el, res){ el.textContent = (res.ok ? '通过 ✅ ' : '失败 ❌ ') + (res.msg || ''); el.className = res.ok ? 'ok mono' : 'err mono'; }
  function setCfg(el, ok){ el.textContent = ok ? 'Supabase 配置就绪 ✅' : 'Supabase 未就绪 ❌（检查 supabase.config.js 与 assets/supabase.js）'; el.className = ok ? 'ok mono' : 'err mono'; }
  function isSupabaseConfigValid(){ try{ const u=(window.__SUPABASE__&&window.__SUPABASE__.url)||''; const a=(window.__SUPABASE__&&window.__SUPABASE__.anon)||''; const okDomain=/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(u)&&!/your-project\.supabase\.co/i.test(u); return !!(window.supabase && okDomain && a && a.length>20); }catch(e){ return false; } }
  async function getClient(){ if(!isSupabaseConfigValid()) throw new Error('Supabase 未就绪'); if(!window.supabaseClient) window.supabaseClient = window.supabase.createClient(window.__SUPABASE__.url, window.__SUPABASE__.anon); return window.supabaseClient; }
  async function ensureLogin(){ const c = await getClient(); let { data: sess } = await c.auth.getSession(); let user = sess && sess.session && sess.session.user || null; if(!user){ const email='diagnostic+'+Date.now()+'@example.com'; const password='Diag_'+Math.random().toString(36).slice(2)+'Aa1!'; try{ await c.auth.signUp({ email, password }); }catch(_){ } const si = await c.auth.signInWithPassword({ email, password }); if(si && si.error) throw new Error(si.error.message); ({ data: sess } = await c.auth.getSession()); user = sess && sess.session && sess.session.user || null; } return { c, user }; }
  async function refreshIfExpired(c){ try{ await c.auth.refreshSession(); }catch(_){ } return c; }

  // 诊断日志：写入 app_diagnostics_log（若不存在则静默失败）
  async function logAction(c, payload){ try{ const base = { ts: new Date().toISOString() }; await c.from('app_diagnostics_log').insert(Object.assign(base, payload)); }catch(_){ /* ignore logging failures */ } }

  async function testAnonKVRead(){ if(!isSupabaseConfigValid()) return { ok:false, msg:'配置未就绪' }; try{ const url=(window.__SUPABASE__&&window.__SUPABASE__.url||'').replace(/\/$/,''); const anon=(window.__SUPABASE__&&window.__SUPABASE__.anon)||''; const p=new URLSearchParams(); p.append('select','key'); p.append('key','eq.taixuanVipCodes'); p.append('limit','1'); const r=await fetch(url+'/rest/v1/app_kv_store?'+p.toString(),{ headers:{ 'apikey':anon,'Content-Type':'application/json' } }); const j=await (async()=>{ try{ return await r.json(); }catch(_){ return null; } })(); if(!r.ok) return { ok:false, msg:(j && j.message)||r.statusText||'读取失败' }; return { ok:true, msg:'可读取' }; }catch(e){ return { ok:false, msg: e&&e.message?e.message:String(e) }; } }

  async function testKVUpdatedBy(){ try{ let { c, user } = await ensureLogin(); const key='diag_updated_by_'+Date.now(); let { error: e1 } = await c.from('app_kv_store').upsert({ key, value:{ ts:Date.now() }, updated_at:new Date().toISOString() }, { onConflict:'key' }); if(e1 && /JWT expired/i.test(e1.message)){ await refreshIfExpired(c); ({ error: e1 } = await c.from('app_kv_store').upsert({ key, value:{ ts:Date.now() }, updated_at:new Date().toISOString() }, { onConflict:'key' })); }
    if(e1){ ({ c, user } = await ensureLogin()); ({ error: e1 } = await c.from('app_kv_store').upsert({ key, value:{ ts:Date.now() }, updated_at:new Date().toISOString() }, { onConflict:'key' })); }
    if(e1){ await logAction(c, { action:'kv_write_updated_by', status:'error', message:e1.message, user_id:user.id, email:user.email }); return { ok:false, msg:'写入失败：'+e1.message }; }
    const { data, error: e2 } = await c.from('app_kv_store').select('updated_by').eq('key', key).limit(1).maybeSingle(); if(e2){ await logAction(c, { action:'kv_read_updated_by', status:'error', message:e2.message, user_id:user.id, email:user.email }); return { ok:false, msg:'读取失败：'+e2.message }; }
    const ok=!!(data && data.updated_by && data.updated_by===user.id); await logAction(c, { action:'kv_write_updated_by', status: ok?'ok':'mismatch', message: ok?('updated_by='+data.updated_by):'updated_by 不匹配或为空', user_id:user.id, email:user.email });
    return { ok, msg: ok?('updated_by='+data.updated_by):('updated_by 不匹配或为空') };
  }catch(e){ return { ok:false, msg: e&&e.message?e.message:String(e) }; }
  }

  async function testStudentOwnership(){ try{ let { c, user } = await ensureLogin(); const email=(user.email||'').trim(); const payloadMin={ email, user_id:user.id };
    let { error:e1 } = await c.from('students').upsert(payloadMin); if(e1 && /JWT expired/i.test(e1.message)){ await refreshIfExpired(c); ({ error:e1 } = await c.from('students').upsert(payloadMin)); }
    try{ await c.rpc('link_my_student_record'); }catch(e){ if(/JWT expired/i.test(e.message)){ await refreshIfExpired(c); try{ await c.rpc('link_my_student_record'); }catch(_){ } } }
    try{ await c.rpc('ensure_my_student_row'); }catch(e){ if(/JWT expired/i.test(e.message)){ await refreshIfExpired(c); try{ await c.rpc('ensure_my_student_row'); }catch(_){ } } }
    if(e1){ await logAction(c, { action:'student_upsert', status:'error', message:e1.message, user_id:user.id, email:user.email }); return { ok:false, msg:'写入失败：'+e1.message }; }
    let r1 = await c.from('students').select('user_id').eq('user_id', user.id).limit(1).maybeSingle(); if(r1 && r1.error && /JWT expired/i.test(r1.error.message)){ await refreshIfExpired(c); r1 = await c.from('students').select('user_id').eq('user_id', user.id).limit(1).maybeSingle(); }
    let ok = !!(r1 && r1.data && r1.data.user_id);
    if(!ok){ let byMailObj = await c.from('students').select('email,user_id').ilike('email','%'+email+'%'); if(byMailObj && byMailObj.error && /JWT expired/i.test(byMailObj.error.message)){ await refreshIfExpired(c); byMailObj = await c.from('students').select('email,user_id').ilike('email','%'+email+'%'); } const byMail = Array.isArray(byMailObj && byMailObj.data) ? byMailObj.data : []; const exactRows = byMail.filter(r => (r.email||'').toLowerCase()===email.toLowerCase()); const someHasUid = exactRows.some(r => r.user_id && String(r.user_id).length>0);
      if(exactRows.length>0 && !someHasUid){ try{ await c.rpc('link_my_student_record'); await c.rpc('ensure_my_student_row'); }catch(_){ } byMailObj = await c.from('students').select('email,user_id').ilike('email','%'+email+'%'); }
      ok = someHasUid || !!(r1 && r1.data && r1.data.user_id);
      if(ok){ await logAction(c, { action:'student_ownership', status:'ok', message:'读取到本人记录（按邮箱或 user_id）', user_id:user.id, email:user.email }); return { ok:true, msg:'读取到本人记录（按邮箱或 user_id）' }; }
      if(exactRows.length>0){ await logAction(c, { action:'student_ownership', status:'missing_uid', message:'命中邮箱但未绑定 user_id（需执行策略或RPC）', user_id:user.id, email:user.email }); return { ok:false, msg:'命中邮箱但未绑定 user_id（需执行策略或RPC）' }; }
    }
    await logAction(c, { action:'student_ownership', status: ok?'ok':'not_found', message: ok?'读取到本人记录':('无本人记录（uid='+user.id+', email='+email+')'), user_id:user.id, email:user.email });
    return { ok, msg: ok?('读取到本人记录'):('无本人记录（uid='+user.id+', email='+email+')') };
  }catch(e){ return { ok:false, msg: e&&e.message?e.message:String(e) }; }
  }

  async function runAll(){ const cfgEl=document.getElementById('cfg'); setCfg(cfgEl, isSupabaseConfigValid()); const elAnon=document.getElementById('diag_anon'); const elUpd=document.getElementById('diag_upd'); const elStu=document.getElementById('diag_stu'); elAnon.textContent='检测中…'; elUpd.textContent='检测中…'; elStu.textContent='检测中…'; const r1=await testAnonKVRead(); const r2=await testKVUpdatedBy(); const r3=await testStudentOwnership(); setText(elAnon,r1); setText(elUpd,r2); setText(elStu,r3); const summary=document.getElementById('summary'); const okCount=[r1,r2,r3].filter(x=>x.ok).length; const total=3; summary.textContent=`运行时间：${new Date().toLocaleString()} | 通过 ${okCount}/${total} | 详情：匿名KV(${r1.ok?'✅':'❌'}), updated_by(${r2.ok?'✅':'❌'}), 归属(${r3.ok?'✅':'❌'})`;
  }

  if(document.readyState==='loading'){ document.addEventListener('DOMContentLoaded', runAll); } else { runAll(); }
  try{ document.getElementById('btnRun').addEventListener('click', runAll); }catch(_){ }
})();