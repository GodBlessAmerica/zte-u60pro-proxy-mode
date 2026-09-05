package main

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	listenAddr = "10.66.0.1:8081"
	proxyMode  = "/data/proxy-mode/bin/proxy-mode"
	singBox    = "/data/proxy-mode/bin/sing-box"
	tokenFile  = "/data/proxy-mode/runtime/web.token"
	configDir  = "/data/proxy-mode/configs"
	lanIf      = "br-lan"
	maxJSON    = 256 << 10
)

var (
	macRE  = regexp.MustCompile(`(?i)^([0-9a-f]{2}:){5}[0-9a-f]{2}$`)
	modeRE = regexp.MustCompile(`^mode([1-9][0-9]?)\.json$`)
)

type statusData map[string]string
type apiReply map[string]any

type client struct {
	IP, MAC, State, Policy string
}

type modeInfo struct {
	Number      int    `json:"number"`
	Name        string `json:"name"`
	Label       string `json:"label"`
	Description string `json:"description"`
	Current     bool   `json:"current"`
}

func run(args ...string) (string, error) {
	b, err := exec.Command(proxyMode, args...).CombinedOutput()
	return strings.TrimSpace(string(b)), err
}

func parseKV(out string) statusData {
	d := statusData{}
	for _, line := range strings.Split(out, "\n") {
		if k, v, ok := strings.Cut(line, "="); ok {
			d[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	return d
}

func status() statusData {
	out, err := run("status")
	if err != nil {
		return statusData{"state": "error", "error": out}
	}
	d := parseKV(out)
	if _, ok := d["udp_quic_guard"]; !ok { d["udp_quic_guard"] = "strict" }
	if v, ok := d["ipv6_guard"]; ok { d["ipv6_leak_guard"] = v }
	if _, ok := d["ipv6_leak_guard"]; !ok { d["ipv6_leak_guard"] = "unknown" }
	return d
}

func tokenOK(r *http.Request) bool {
	want, err := os.ReadFile(tokenFile)
	if err != nil { return false }
	got := []byte(strings.TrimSpace(r.Header.Get("X-Proxy-Token")))
	want = []byte(strings.TrimSpace(string(want)))
	return len(got) == len(want) && len(want) > 0 && subtle.ConstantTimeCompare(got, want) == 1
}

func requireToken(w http.ResponseWriter, r *http.Request) bool {
	if tokenOK(r) { return true }
	writeJSON(w, 403, apiReply{"ok": false, "error": "invalid token"})
	return false
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func clients() []client {
	out, _ := exec.Command("ip", "neigh", "show", "dev", lanIf).Output()
	st := status()
	proxySet, directSet := map[string]bool{}, map[string]bool{}
	for _, x := range strings.Fields(st["proxy_devices"]) { proxySet[strings.ToLower(strings.TrimPrefix(x, "mac:"))] = true }
	for _, x := range strings.Fields(st["direct_devices"]) { directSet[strings.ToLower(strings.TrimPrefix(x, "mac:"))] = true }
	var list []client
	seen := map[string]bool{}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 { continue }
		ip := net.ParseIP(f[0]); if ip == nil || ip.To4() == nil { continue }
		mac := ""
		for i := 1; i+1 < len(f); i++ { if f[i] == "lladdr" { mac = strings.ToLower(f[i+1]); break } }
		if !macRE.MatchString(mac) || seen[mac] { continue }
		seen[mac] = true
		policy := "direct"
		if proxySet[mac] { policy = "proxy" } else if directSet[mac] { policy = "direct" }
		list = append(list, client{f[0], mac, f[len(f)-1], policy})
	}
	sort.Slice(list, func(i, j int) bool { return list[i].IP < list[j].IP })
	return list
}

func modeMeta(n int) (string, string) {
	switch n {
	case 4: return "VLESS Reality", "Stable · TCP + proxied DNS"
	case 5: return "SSH Direct", "SSH server as exit"
	case 6: return "SSH → SOCKS5", "Remote SOCKS5 through SSH"
	case 7: return "SSH Jump", "A jump host → B exit"
	case 8: return "LAN SOCKS5", "Use a SOCKS5 proxy on LAN"
	case 9: return "LAN HTTP", "Use an HTTP proxy on LAN"
	case 10: return "VLESS TPROXY", "Legacy experiment · not recommended"
	case 11: return "VLESS Full Proxy", "Validated · TCP REDIRECT + UDP TUN/XUDP"
	default: return fmt.Sprintf("Mode %d", n), "Custom sing-box configuration"
	}
}

func listModes() []modeInfo {
	entries, _ := os.ReadDir(configDir)
	current := status()["mode"]
	var out []modeInfo
	for _, e := range entries {
		if e.IsDir() { continue }
		m := modeRE.FindStringSubmatch(e.Name()); if len(m) != 2 { continue }
		n, _ := strconv.Atoi(m[1]); label, desc := modeMeta(n)
		out = append(out, modeInfo{n, e.Name(), label, desc, current == m[1]})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Number < out[j].Number })
	return out
}

func parseModeNumber(r *http.Request) (int, error) {
	n, err := strconv.Atoi(r.URL.Query().Get("number"))
	if err != nil || n < 1 || n > 99 { return 0, fmt.Errorf("mode number must be 1-99") }
	return n, nil
}
func modePath(n int) string { return filepath.Join(configDir, fmt.Sprintf("mode%d.json", n)) }

func getModeJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet { writeJSON(w, 405, apiReply{"ok": false, "error": "GET required"}); return }
	if !requireToken(w, r) { return }
	n, err := parseModeNumber(r); if err != nil { writeJSON(w, 400, apiReply{"ok": false, "error": err.Error()}); return }
	b, err := os.ReadFile(modePath(n)); if err != nil { writeJSON(w, 404, apiReply{"ok": false, "error": "mode not found"}); return }
	var obj any
	if json.Unmarshal(b, &obj) == nil { if p, err := json.MarshalIndent(obj, "", "  "); err == nil { b = p } }
	writeJSON(w, 200, apiReply{"ok": true, "number": n, "content": string(b)})
}

func saveModeJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost { writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"}); return }
	if !requireToken(w, r) { return }
	n, err := parseModeNumber(r); if err != nil { writeJSON(w, 400, apiReply{"ok": false, "error": err.Error()}); return }
	r.Body = http.MaxBytesReader(w, r.Body, maxJSON)
	body, err := io.ReadAll(r.Body); if err != nil { writeJSON(w, 400, apiReply{"ok": false, "error": "request body too large or unreadable"}); return }
	body = []byte(strings.TrimSpace(string(body))); if len(body) == 0 || !json.Valid(body) { writeJSON(w, 400, apiReply{"ok": false, "error": "invalid JSON"}); return }
	if err := os.MkdirAll(configDir, 0700); err != nil { writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()}); return }
	tmp, err := os.CreateTemp(configDir, fmt.Sprintf(".mode%d-upload-*", n)); if err != nil { writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()}); return }
	tmpPath := tmp.Name(); defer os.Remove(tmpPath); _ = tmp.Chmod(0600); _, _ = tmp.Write(body); _ = tmp.Sync(); _ = tmp.Close()
	checkOut, err := exec.Command(singBox, "check", "-c", tmpPath).CombinedOutput(); if err != nil { writeJSON(w, 400, apiReply{"ok": false, "error": "sing-box check failed", "details": strings.TrimSpace(string(checkOut))}); return }
	dst := modePath(n); if old, err := os.ReadFile(dst); err == nil { _ = os.WriteFile(dst+".bak-web", old, 0600) }
	if err := os.Rename(tmpPath, dst); err != nil { writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()}); return }
	_ = os.Chmod(dst, 0600); writeJSON(w, 200, apiReply{"ok": true, "message": fmt.Sprintf("Mode %d saved and validated", n)})
}

const page = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>U60 Proxy</title><style>
:root{color-scheme:dark;--bg:#091018;--panel:#101923;--line:#243244;--muted:#91a3b7;--text:#eef4fa;--ok:#58d68d;--warn:#f5c451}*{box-sizing:border-box}body{margin:0;background:#091018;color:var(--text);font-family:Inter,system-ui,-apple-system,Segoe UI,sans-serif}.wrap{max-width:1120px;margin:auto;padding:28px 18px 60px}.top{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:18px}.title{font-size:28px;font-weight:760}.sub,.note,.meta,.msg{color:var(--muted);font-size:12px}.pill,.tag{border:1px solid var(--line);border-radius:999px;padding:6px 9px;font-size:11px}.ok{color:#b8f6ce;border-color:#2f6f4d;background:#12311f}.warn{color:#ffe39a;border-color:#6f5a28;background:#2d2613}.stats{display:grid;grid-template-columns:repeat(6,1fr);gap:9px}.card,.panel{background:#101923;border:1px solid var(--line);border-radius:15px}.card{padding:14px}.card span{display:block;color:var(--muted);font-size:10px;margin-bottom:5px}.panel{padding:17px;margin-top:13px}.head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;margin-bottom:12px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.box,.mode{border:1px solid var(--line);border-radius:12px;background:#0d151e;padding:13px}.mode{cursor:pointer}.mode.active{border-color:#3a805b;background:#102a1d}.actions{display:flex;gap:7px;flex-wrap:wrap}button{border:1px solid #33475d;background:#172331;color:var(--text);padding:8px 10px;border-radius:8px;font-weight:650;cursor:pointer}button.active{background:#153a27;border-color:#2f7650}.client{display:grid;grid-template-columns:1fr auto;gap:12px;align-items:center;padding:12px 0;border-top:1px solid var(--line)}.client:first-child{border-top:0}.tags{display:flex;gap:5px;flex-wrap:wrap;margin-top:6px}details{margin-top:13px;border-top:1px solid var(--line);padding-top:13px}textarea{width:100%;min-height:320px;background:#09121b;color:var(--text);border:1px solid #304257;border-radius:9px;padding:9px;margin-top:8px;font:12px/1.45 ui-monospace,Consolas,monospace}input{width:72px;background:#09121b;color:var(--text);border:1px solid #304257;border-radius:8px;padding:8px}@media(max-width:850px){.stats{grid-template-columns:repeat(3,1fr)}.grid{grid-template-columns:1fr 1fr}}@media(max-width:560px){.stats,.grid{grid-template-columns:1fr}.client{grid-template-columns:1fr}}
</style></head><body><div class="wrap">
<div class="top"><div><div class="title">U60 Proxy Control</div><div class="sub">Per-device transparent proxy with validated UDP Full Proxy mode</div></div><span id="state" class="pill">Unknown</span></div>
<div class="stats"><div class="card"><span>MODE</span><strong id="mode">—</strong></div><div class="card"><span>TCP</span><strong id="tcp">—</strong></div><div class="card"><span>UDP</span><strong id="udp">—</strong></div><div class="card"><span>DNS</span><strong id="dns">—</strong></div><div class="card"><span>IPV6</span><strong id="v6">—</strong></div><div class="card"><span>FAIL-CLOSED</span><strong id="fc">—</strong></div></div>
<div class="panel"><div class="head"><div><strong>Traffic & protection</strong><div class="note">Mode 11 keeps TCP on REDIRECT and routes selected-client UDP through u60udp0.</div></div><button id="refresh">Refresh</button></div><div class="grid">
<div class="box"><b>Client policy</b><div class="note">Choose who uses the proxy.</div><div class="actions"><button data-t="selective">Per-device</button><button data-t="on">Proxy all</button><button data-t="off">Direct all</button></div></div>
<div class="box"><b>UDP / QUIC guard</b><div class="note">Strict is recommended. Mode 11 inserts only the marked TUN allow ahead of the guard.</div><div class="actions"><button data-udp="strict">Strict</button><button data-udp="off">Off</button></div></div>
<div class="box"><b>IPv6 leak guard</b><div class="note">Strict prevents proxied clients from bypassing over native IPv6.</div><div class="actions"><button data-v6="strict">Strict</button><button data-v6="off">Off</button></div></div>
</div><div id="msg" class="msg">Ready.</div></div>
<div class="panel"><div class="head"><div><strong>Full Proxy UDP <span id="fullState" class="pill">OFF</span></strong><div class="note">Validated path: MARK 0x67 → table 167 → u60udp0 → VLESS/XUDP. Blackhole fallback prevents cellular UDP fallback.</div></div></div><div class="actions"><button id="fullOn">Enable / repair</button><button id="fullOff">Disable</button></div><div id="fullMsg" class="msg">Mode 11 enables this automatically after sing-box starts.</div></div>
<div class="panel"><div class="head"><div><strong>Modes</strong><div class="note">Mode 11 is the validated Full Proxy mode. Mode 10 is retained only as the old TPROXY experiment.</div></div></div><div id="modegrid" class="grid"></div><details><summary>JSON editor</summary><div class="actions" style="margin-top:10px"><label>Mode <input id="modeNumber" type="number" min="1" max="99" value="4"></label><button id="loadMode">Load</button><button id="activateMode">Activate</button><button id="saveMode">Validate & save</button><button id="saveStartMode">Save & activate</button></div><textarea id="modeJson" spellcheck="false"></textarea><div id="modeMsg" class="msg"></div></details></div>
<div class="panel"><div class="head"><div><strong>Connected devices</strong><div class="note">Policy is tied to MAC address.</div></div></div><div id="clients"></div></div>
</div><script>
const $=id=>document.getElementById(id);let S={};function tok(){let t=localStorage.getItem('u60ProxyToken')||'';if(!t){t=prompt('Control token')||'';if(t)localStorage.setItem('u60ProxyToken',t)}return t}async function getj(p){let r=await fetch(p,{cache:'no-store'}),j=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.error||('HTTP '+r.status));return j}async function authget(p){let t=tok();if(!t)throw Error('token required');let r=await fetch(p,{headers:{'X-Proxy-Token':t},cache:'no-store'}),j=await r.json().catch(()=>({}));if(r.status===403)localStorage.removeItem('u60ProxyToken');if(!r.ok)throw Error(j.error||('HTTP '+r.status));return j}async function post(p,b=''){let t=tok();if(!t)throw Error('token required');let r=await fetch(p,{method:'POST',headers:{'X-Proxy-Token':t,'Content-Type':'application/json'},body:b}),j=await r.json().catch(()=>({}));if(r.status===403)localStorage.removeItem('u60ProxyToken');if(!r.ok)throw Error((j.error||('HTTP '+r.status))+(j.details?' · '+j.details:''));return j}function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}function pretty(v){return (v||'—').replaceAll('_',' ')}function render(s){S=s;$('mode').textContent=s.mode&&s.mode!=='unconfigured'?'Mode '+s.mode:'Not configured';$('tcp').textContent=s.state==='running'?'Proxy ON':'OFF';$('udp').textContent=s.full_proxy_udp==='on'?'TUN ON':(s.udp_quic_guard==='strict'?'Blocked':'Direct');$('dns').textContent=pretty(s.dns_proxy);$('v6').textContent=pretty(s.ipv6_leak_guard);$('fc').textContent=s.udp_fail_closed==='yes'?'ON':'—';$('state').textContent=s.state==='running'?'Engine running':'Engine '+(s.state||'unknown');$('state').className='pill '+(s.state==='running'?'ok':'warn');$('fullState').textContent=s.full_proxy_udp==='on'?'ON':'OFF';$('fullState').className='pill '+(s.full_proxy_udp==='on'?'ok':'');document.querySelectorAll('[data-t]').forEach(b=>b.classList.toggle('active',b.dataset.t===(s.traffic_mode==='all'?'on':s.traffic_mode==='off'?'off':'selective')));document.querySelectorAll('[data-udp]').forEach(b=>b.classList.toggle('active',b.dataset.udp===s.udp_quic_guard));document.querySelectorAll('[data-v6]').forEach(b=>b.classList.toggle('active',b.dataset.v6===s.ipv6_leak_guard))}function tags(c){if(c.Policy==='proxy'||c.policy==='proxy'){let udp=S.full_proxy_udp==='on'?'<span class="tag ok">UDP TUN</span>':(S.udp_quic_guard==='strict'?'<span class="tag warn">UDP blocked</span>':'<span class="tag warn">UDP direct</span>');return '<span class="tag ok">Proxy</span><span class="tag ok">DNS</span>'+udp+'<span class="tag">IPv6 '+pretty(S.ipv6_leak_guard)+'</span>'}return '<span class="tag">Direct</span>'}
async function refreshModes(){let d=await getj('/api/modes'),box=$('modegrid');box.innerHTML='';(d.modes||[]).forEach(m=>{let x=document.createElement('div');x.className='mode'+(m.current?' active':'');x.innerHTML='<div class="meta">MODE '+m.number+(m.current?' · ACTIVE':'')+'</div><b>'+esc(m.label)+'</b><div class="note">'+esc(m.description)+'</div>';x.onclick=()=>loadMode(m.number);box.appendChild(x)})}
async function refresh(){try{let s=await getj('/api/status');render(s);let d=await getj('/api/clients'),box=$('clients');box.innerHTML='';(d.clients||[]).forEach(c=>{let ip=c.IP||c.ip,mac=c.MAC||c.mac,state=c.State||c.state,policy=c.Policy||c.policy;let r=document.createElement('div');r.className='client';r.innerHTML='<div><b>'+esc(ip)+'</b><div class="meta">'+esc(mac)+' · '+esc(state)+'</div><div class="tags">'+tags(c)+'</div></div><div class="actions"><button data-a="proxy" class="'+(policy==='proxy'?'active':'')+'">Proxy</button><button data-a="direct" class="'+(policy==='direct'?'active':'')+'">Direct</button></div>';r.querySelector('[data-a=proxy]').onclick=()=>dev(mac,'proxy');r.querySelector('[data-a=direct]').onclick=()=>dev(mac,'direct');box.appendChild(r)});await refreshModes();$('msg').textContent='Updated.'}catch(e){$('msg').textContent='Refresh failed: '+e.message}}
async function action(p,msg){try{$('msg').textContent=msg;await post(p);await refresh()}catch(e){$('msg').textContent='Action failed: '+e.message}}async function dev(m,a){await action('/api/device?selector='+encodeURIComponent(m)+'&action='+a,'Updating device…')}async function loadMode(n){n=n||parseInt($('modeNumber').value,10);try{let j=await authget('/api/mode?number='+n);$('modeNumber').value=n;$('modeJson').value=j.content||'';$('modeMsg').textContent='Mode '+n+' loaded.';$('modeJson').closest('details').open=true}catch(e){$('modeMsg').textContent=e.message}}async function activateMode(n){n=n||parseInt($('modeNumber').value,10);try{let j=await post('/api/mode/activate?number='+n);$('modeMsg').textContent=j.message;await refresh()}catch(e){$('modeMsg').textContent=e.message}}async function saveMode(start){let n=parseInt($('modeNumber').value,10),b=$('modeJson').value.trim();try{JSON.parse(b)}catch(e){$('modeMsg').textContent='JSON error: '+e.message;return}try{let j=await post('/api/mode/save?number='+n,b);$('modeMsg').textContent=j.message;if(start)await activateMode(n);else await refreshModes()}catch(e){$('modeMsg').textContent=e.message}}async function fp(a){try{let j=await post('/api/fullproxy?action='+a);$('fullMsg').textContent=j.message||'Done';await refresh()}catch(e){$('fullMsg').textContent=e.message}}
document.querySelectorAll('[data-t]').forEach(b=>b.onclick=()=>action('/api/traffic?action='+b.dataset.t,'Applying traffic policy…'));document.querySelectorAll('[data-udp]').forEach(b=>b.onclick=()=>action('/api/guard?kind=udp&value='+b.dataset.udp,'Applying UDP guard…'));document.querySelectorAll('[data-v6]').forEach(b=>b.onclick=()=>action('/api/guard?kind=ipv6&value='+b.dataset.v6,'Applying IPv6 guard…'));$('refresh').onclick=refresh;$('fullOn').onclick=()=>fp('on');$('fullOff').onclick=()=>fp('off');$('loadMode').onclick=()=>loadMode();$('activateMode').onclick=()=>activateMode();$('saveMode').onclick=()=>saveMode(false);$('saveStartMode').onclick=()=>saveMode(true);refresh();setInterval(refresh,15000);
</script></body></html>`

var tmpl = template.Must(template.New("page").Parse(page))

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) { if r.URL.Path != "/" { http.NotFound(w,r); return }; w.Header().Set("Content-Type","text/html; charset=utf-8"); w.Header().Set("Cache-Control","no-store"); _=tmpl.Execute(w,nil) })
	mux.HandleFunc("/api/status", func(w http.ResponseWriter,r *http.Request){ writeJSON(w,200,status()) })
	mux.HandleFunc("/api/clients", func(w http.ResponseWriter,r *http.Request){ writeJSON(w,200,apiReply{"ok":true,"clients":clients()}) })
	mux.HandleFunc("/api/modes", func(w http.ResponseWriter,r *http.Request){ writeJSON(w,200,apiReply{"ok":true,"modes":listModes()}) })
	mux.HandleFunc("/api/mode", getModeJSON)
	mux.HandleFunc("/api/mode/save", saveModeJSON)
	mux.HandleFunc("/api/mode/activate", func(w http.ResponseWriter,r *http.Request){ if r.Method!=http.MethodPost{writeJSON(w,405,apiReply{"ok":false,"error":"POST required"});return};if !requireToken(w,r){return};n,e:=parseModeNumber(r);if e!=nil{writeJSON(w,400,apiReply{"ok":false,"error":e.Error()});return};o,e:=run("restart",strconv.Itoa(n));if e!=nil{writeJSON(w,500,apiReply{"ok":false,"error":o});return};writeJSON(w,200,apiReply{"ok":true,"message":o}) })
	mux.HandleFunc("/api/traffic", func(w http.ResponseWriter,r *http.Request){ if r.Method!=http.MethodPost{writeJSON(w,405,apiReply{"ok":false,"error":"POST required"});return};if !requireToken(w,r){return};a:=r.URL.Query().Get("action");if a!="on"&&a!="off"&&a!="selective"{writeJSON(w,400,apiReply{"ok":false,"error":"invalid action"});return};o,e:=run("traffic",a);if e!=nil{writeJSON(w,500,apiReply{"ok":false,"error":o});return};writeJSON(w,200,apiReply{"ok":true,"message":o}) })
	mux.HandleFunc("/api/guard", func(w http.ResponseWriter,r *http.Request){ if r.Method!=http.MethodPost{writeJSON(w,405,apiReply{"ok":false,"error":"POST required"});return};if !requireToken(w,r){return};k,v:=r.URL.Query().Get("kind"),r.URL.Query().Get("value");if(k!="udp"&&k!="ipv6")||(v!="strict"&&v!="off"){writeJSON(w,400,apiReply{"ok":false,"error":"invalid guard"});return};o,e:=run("guard",k,v);if e!=nil{writeJSON(w,500,apiReply{"ok":false,"error":o});return};writeJSON(w,200,apiReply{"ok":true,"message":o}) })
	mux.HandleFunc("/api/fullproxy", func(w http.ResponseWriter,r *http.Request){ if r.Method!=http.MethodPost{writeJSON(w,405,apiReply{"ok":false,"error":"POST required"});return};if !requireToken(w,r){return};a:=r.URL.Query().Get("action");if a!="on"&&a!="apply"&&a!="off"&&a!="status"{writeJSON(w,400,apiReply{"ok":false,"error":"invalid action"});return};o,e:=run("fullproxy",a);if e!=nil{writeJSON(w,500,apiReply{"ok":false,"error":o});return};writeJSON(w,200,apiReply{"ok":true,"message":o}) })
	mux.HandleFunc("/api/device", func(w http.ResponseWriter,r *http.Request){ if r.Method!=http.MethodPost{writeJSON(w,405,apiReply{"ok":false,"error":"POST required"});return};if !requireToken(w,r){return};m,a:=strings.ToLower(r.URL.Query().Get("selector")),r.URL.Query().Get("action");if !macRE.MatchString(m)||(a!="proxy"&&a!="direct"){writeJSON(w,400,apiReply{"ok":false,"error":"invalid selector/action"});return};o,e:=run("device",m,a);if e!=nil{writeJSON(w,500,apiReply{"ok":false,"error":o});return};writeJSON(w,200,apiReply{"ok":true,"message":o}) })
	s:=&http.Server{Addr:listenAddr,Handler:mux,ReadHeaderTimeout:5*time.Second,ReadTimeout:15*time.Second,WriteTimeout:30*time.Second,IdleTimeout:60*time.Second};log.Printf("u60-web listening on http://%s/",listenAddr);log.Fatal(s.ListenAndServe())
}
