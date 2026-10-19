#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod server;

use std::{cell::RefCell, rc::Rc, time::{Duration, Instant}};
use tao::{dpi::LogicalSize, event::{Event, WindowEvent}, event_loop::{ControlFlow, EventLoop}, window::WindowBuilder};
use wry::WebViewBuilder;

fn main() {
    let event_loop = EventLoop::new();
    let window = match WindowBuilder::new().with_title("AETHER").with_inner_size(LogicalSize::new(1280.0, 840.0)).with_min_inner_size(LogicalSize::new(940.0, 620.0)).build(&event_loop) {
        Ok(w) => w, Err(e) => { eprintln!("AETHER: could not create window: {e}"); return; }
    };
    let (url, supervisor, failure) = match server::launch() {
        Ok((url, child)) => (url, child, None),
        Err(e) => { server::record_failure(&e); ("about:blank".to_string(), None, Some(e)) }
    };
    let webview = if let Some(message) = failure.as_ref() {
        server::record_failure(message);
        WebViewBuilder::new().with_html(&server::error_page(message)).with_navigation_handler(|uri| uri == "about:blank").build(&window)
    } else {
        let origin = url.split('/').take(3).collect::<Vec<_>>().join("/");
        let token = server::owner_token().unwrap_or_default();
        let page = native_page(&url, &token);
        WebViewBuilder::new().with_html(&page).with_navigation_handler(move |uri| {
            if uri.starts_with(&origin) { true } else { let _ = webbrowser::open(&uri); false }
        }).build(&window)
    };
    let webview = match webview { Ok(v) => v, Err(e) => { server::record_failure(&format!("Webview startup failed: {e}")); eprintln!("AETHER: webview startup failed: {e}"); return; } };
    let webview = Rc::new(webview);
    let supervisor = Rc::new(RefCell::new(supervisor));
    let sup = supervisor.clone(); let view = webview.clone(); let mut next_check = Instant::now();
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(next_check);
        match event {
            Event::MainEventsCleared if Instant::now() >= next_check => { next_check = Instant::now() + Duration::from_secs(1); if let Some(message) = server::check_exit(&mut sup.borrow_mut()) { let escaped = message.replace('\\', "\\\\").replace('\'', "\\'"); let script = format!("document.body.innerHTML='<h1>AETHER server stopped</h1><p>{escaped}</p>'"); let _ = view.evaluate_script(&script); } }
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => { server::stop(&mut sup.borrow_mut()); *control_flow = ControlFlow::Exit; }
            Event::LoopDestroyed => server::stop(&mut sup.borrow_mut()), _ => {}
        }
    });
}

fn native_page(url: &str, token: &str) -> String {
    let base = format!("{}/api", url.trim_end_matches('/'));
    let js = format!(r#"
const BASE={base:?}, INITIAL_TOKEN={token:?}; let token=sessionStorage.getItem('opendots-token')||INITIAL_TOKEN, data={{}}, pageId='',conversationId='';
const api=async(path,method='GET',body)=>{{let r=await fetch(BASE+path,{{method,headers:{{...(token?{{Authorization:'Bearer '+token}}:{{}}),...(method==='GET'?{{}}:{{'Content-Type':'application/json'}})}},...(body===undefined?{{}}:{{body:JSON.stringify(body)}})}});let x=await r.json().catch(()=>({{}}));if(!r.ok)throw Error(x.error||'Request failed ('+r.status+')');return x}};
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
async function load(){{try{{[data.state,data.workspace]=await Promise.all([api('/state'),api('/workspace')]);render()}}catch(e){{document.querySelector('#content').innerHTML='<section class=card><h1>Unlock your workspace</h1><p>'+esc(e.message)+'</p><input id=auth type=password placeholder="Owner access token"><button onclick="unlock()">Unlock</button></section>'}}}}
async function unlock(){{token=document.querySelector('#auth').value;sessionStorage.setItem('opendots-token',token);load()}}
function nav(view){{document.querySelectorAll('[data-view]').forEach(x=>x.classList.toggle('active',x.dataset.view===view));data.view=view;render()}}
function render(){{let v=data.view||'home',w=data.workspace||{{}},s=data.state||{{settings:{{}},tasks:[],memories:[]}},c=document.querySelector('#content');document.querySelector('#nav').innerHTML=['Home','Conversations','Spaces & Pages','Scheduled & Activity','Memories','Settings'].map((n,i)=>`<button data-view="${{['home','conversations','spaces','activity','memories','settings'][i]}}" class="nav ${{v===['home','conversations','spaces','activity','memories','settings'][i]?'active':''}}" onclick="nav('${{['home','conversations','spaces','activity','memories','settings'][i]}}')">${{n}}</button>`).join('');
if(v==='home')c.innerHTML=`<h1>Good to see you.</h1><p class=muted>Your workspace, at a glance.</p><div class=grid><article class=card><h2>Conversations</h2><p>${{w.conversations?.length||0}} saved conversations</p><button onclick="nav('conversations')">Open conversations</button></article><article class=card><h2>Spaces & pages</h2><p>${{w.spaces?.length||0}} spaces</p><button onclick="nav('spaces')">Browse spaces</button></article><article class=card><h2>Scheduled & activity</h2><p>${{s.tasks?.length||0}} tasks</p><button onclick="nav('activity')">View activity</button></article></div>`;
if(v==='conversations')c.innerHTML=`<h1>Conversations</h1><p class=muted>Native chat can show captured transcripts. Sending turns requires the CopilotKit streaming protocol and is unavailable here.</p><div class=columns><section class=card><button onclick="newConversation()">＋ New conversation</button>${{(w.conversations||[]).map(x=>`<button class=row onclick="openConversation('${{esc(x.id)}}')">${{esc(x.title)}}</button>`).join('')}}</section><section class=card id=transcript>Choose a conversation to load its captured transcript.</section></div>`;
if(v==='spaces')c.innerHTML=`<h1>Spaces & Pages</h1><button onclick="createSpace()">＋ New space</button><div class=columns><section class=card>${{(w.spaces||[]).map(x=>`<button class=row onclick="selectSpace('${{esc(x.id)}')">${{esc(x.name)}}</button>`).join('')}}</section><section class=card id=pages>Select a space.</section></div>`;
if(v==='activity')c.innerHTML=`<h1>Scheduled & Activity</h1><button onclick="createTask()">＋ Create task</button>${{(s.tasks||[]).map(t=>`<article class=card><h3>${{esc(t.prompt)}}</h3><p>${{esc(t.status)}}${{t.error?' · '+esc(t.error):''}}</p><button onclick="taskAction('${{t.id}}','run')">Run</button><button onclick="taskAction('${{t.id}}','pause')">Pause</button><button onclick="taskAction('${{t.id}}','cancel')">Cancel</button></article>`).join('')}}</section>`;
if(v==='memories')c.innerHTML=`<h1>Memories</h1>${{(s.memories||[]).map(m=>`<article class=card>${{esc(m.text)}}</article>`).join('')||'<p class=muted>No saved memories.</p>'}}`;
if(v==='settings')c.innerHTML=`<h1>Settings</h1><section class=card><label>Name<input id=sname value="${{esc(s.settings.name)}}"></label>${{[['paused','Pause all Dots'],['researchAllowed','Research allowed'],['memoryAllowed','Memory allowed'],['appsAllowed','Connected apps allowed']].map(([k,l])=>`<label class=check><input type=checkbox id="s_${{k}}" ${{s.settings[k]?'checked':''}}> ${{l}}</label>`).join('')}}<button onclick="saveSettings()">Save settings</button><p class=muted>Mode: ${{esc(s.mode)}} · Setup: ${{w.setup?.missing?.length?'required':'ready'}}</p></section>`;
document.querySelectorAll('[data-view]').forEach(x=>x.classList.toggle('active',x.dataset.view===v));}}
async function newConversation(){{let dot=data.workspace.dots[0];if(!dot)return alert('Create a Dot in the web workspace first.');let x=await api('/conversations','POST',{{dotId:dot.id,title:'A new thought'}});conversationId=x.id;await load();nav('conversations');await openConversation(x.id)}}
async function openConversation(id){{conversationId=id;let x=await api('/conversations/'+id+'/capture');document.querySelector('#transcript').innerHTML=x?`<h2>Captured transcript</h2><pre>${{esc(typeof x==='string'?x:JSON.stringify(x,null,2))}}</pre><p class=muted>Transcript capture only. Sending messages is unavailable in this native client.</p>`:'<p>No transcript captured yet.</p>'}}
async function createSpace(){{let name=prompt('Space name');if(!name)return;await api('/spaces','POST',{{name,description:''}});load()}}
async function selectSpace(id){{data.spaceId=id;let ps=await api('/spaces/'+id+'/pages');document.querySelector('#pages').innerHTML=`<button onclick="newPage()">＋ New page</button>${{ps.map(p=>`<button class=row onclick="readPage('${{p.id}}')">${{esc(p.title)}}</button>`).join('')}}<div id=pageeditor></div>`}}
async function newPage(){{let title=prompt('Page title');if(!title)return;let p=await api('/spaces/'+data.spaceId+'/pages','POST',{{title,content:''}});selectSpace(data.spaceId);readPage(p.id)}}
async function readPage(id){{pageId=id;let p=await api('/spaces/'+data.spaceId+'/pages/'+id);document.querySelector('#pageeditor').innerHTML=`<input id=ptitle value="${{esc(p.title)}}"><textarea id=pcontent>${{esc(p.content)}}</textarea><button onclick="savePage()">Save</button><button onclick="deletePage()">Delete</button>`;data.pageRevision=p.revision}}
async function savePage(){{await api('/spaces/'+data.spaceId+'/pages/'+pageId,'PATCH',{{title:document.querySelector('#ptitle').value,content:document.querySelector('#pcontent').value,expectedRevision:data.pageRevision}});selectSpace(data.spaceId)}}
async function deletePage(){{await api('/spaces/'+data.spaceId+'/pages/'+pageId,'DELETE');selectSpace(data.spaceId)}}
async function createTask(){{let prompt=window.prompt('Task request (3–4,000 characters)');if(!prompt)return;await api('/tasks','POST',{{prompt}});load()}}
async function taskAction(id,action){{await api('/tasks/'+id+'/actions','POST',{{action}});load()}}
async function saveSettings(){{let body={{name:document.querySelector('#sname').value}};for(let k of ['paused','researchAllowed','memoryAllowed','appsAllowed'])body[k]=document.querySelector('#s_'+k).checked;await api('/settings','PATCH',body);load()}}
load();
"#);
    format!(r#"<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>AETHER</title><style>
*{{box-sizing:border-box}}body{{margin:0;background:#f8f7f4;color:#333641;font:14px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}}button,input,textarea{{font:inherit}}button{{border:1px solid #e9e8e6;border-radius:9px;background:white;color:inherit;padding:10px 14px;cursor:pointer}}button:hover{{background:#f0f1f8}}.app{{display:flex;min-height:100vh}}aside{{width:245px;padding:30px 18px;background:#fbfaf8;border-right:1px solid #e9e8e6;flex-shrink:0}}.brand{{font-size:23px;font-weight:700;margin:0 12px 35px}}.nav{{display:block;width:100%;text-align:left;border:0;background:none;color:#858690;margin:3px 0;padding:12px 14px}}.nav.active{{background:#eeeff7;color:#596aa9}}main{{padding:52px clamp(24px,6vw,90px);width:100%;max-width:1300px;margin:auto}}h1{{font-weight:550;letter-spacing:-.04em;font-size:32px}}h2{{font-size:19px}}.muted{{color:#8c8d97}}.card{{background:white;border:1px solid #e9e8e6;border-radius:14px;padding:22px;margin:14px 0}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}}.columns{{display:grid;grid-template-columns:minmax(220px, .75fr) 2fr;gap:15px}}.row{{display:block;width:100%;text-align:left;margin-top:8px}}input,textarea{{width:100%;border:1px solid #dedee6;border-radius:9px;padding:11px;background:white;color:inherit;margin:6px 0 14px}}textarea{{min-height:280px}}label{{display:block;margin:15px 0}}.check input{{width:auto}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.7 inherit}}@media(max-width:700px){{.columns{{grid-template-columns:1fr}}aside{{width:190px}}main{{padding:30px 16px}}}}
</style></head><body><div class="app"><aside><div class="brand">◉ OpenDots<span style="color:#a1addc">•</span></div><nav id="nav"></nav><p class="muted" style="margin:40px 12px 0;font-size:10px;letter-spacing:1px">NATIVE WORKSPACE</p></aside><main id="content"><p>Connecting…</p></main></div><script>{js}</script></body></html>"#)
}
