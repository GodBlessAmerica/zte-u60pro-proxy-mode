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
	IP     string `json:"ip"`
	MAC    string `json:"mac"`
	State  string `json:"state"`
	Policy string `json:"policy"`
}

type modeInfo struct {
	Number  int    `json:"number"`
	Name    string `json:"name"`
	Current bool   `json:"current"`
}

func run(args ...string) (string, error) {
	b, err := exec.Command(proxyMode, args...).CombinedOutput()
	return strings.TrimSpace(string(b)), err
}

func parseStatus() statusData {
	out, err := run("status")
	d := statusData{}
	if err != nil {
		d["state"] = "error"
		d["error"] = out
		return d
	}
	for _, line := range strings.Split(out, "\n") {
		if k, v, ok := strings.Cut(line, "="); ok {
			d[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	return d
}

func tokenOK(r *http.Request) bool {
	want, err := os.ReadFile(tokenFile)
	if err != nil {
		return false
	}
	got := []byte(strings.TrimSpace(r.Header.Get("X-Proxy-Token")))
	want = []byte(strings.TrimSpace(string(want)))
	if len(got) != len(want) || len(want) == 0 {
		return false
	}
	return subtle.ConstantTimeCompare(got, want) == 1
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
	st := parseStatus()
	proxySet := map[string]bool{}
	directSet := map[string]bool{}
	for _, x := range strings.Fields(st["proxy_devices"]) {
		proxySet[strings.ToLower(strings.TrimPrefix(x, "mac:"))] = true
	}
	for _, x := range strings.Fields(st["direct_devices"]) {
		directSet[strings.ToLower(strings.TrimPrefix(x, "mac:"))] = true
	}
	list := make([]client, 0)
	seen := map[string]bool{}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 {
			continue
		}
		ip := net.ParseIP(f[0])
		if ip == nil || ip.To4() == nil {
			continue
		}
		mac := ""
		for i := 1; i+1 < len(f); i++ {
			if f[i] == "lladdr" {
				mac = strings.ToLower(f[i+1])
				break
			}
		}
		if !macRE.MatchString(mac) || seen[mac] {
			continue
		}
		seen[mac] = true
		policy := "direct"
		if proxySet[mac] {
			policy = "proxy"
		} else if directSet[mac] {
			policy = "direct"
		}
		list = append(list, client{IP: f[0], MAC: mac, State: f[len(f)-1], Policy: policy})
	}
	return list
}

func listModes() []modeInfo {
	entries, _ := os.ReadDir(configDir)
	current := parseStatus()["mode"]
	out := make([]modeInfo, 0)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := modeRE.FindStringSubmatch(e.Name())
		if len(m) != 2 {
			continue
		}
		n, _ := strconv.Atoi(m[1])
		out = append(out, modeInfo{Number: n, Name: e.Name(), Current: current == m[1]})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Number < out[j].Number })
	return out
}

func parseModeNumber(r *http.Request) (int, error) {
	n, err := strconv.Atoi(r.URL.Query().Get("number"))
	if err != nil || n < 1 || n > 99 {
		return 0, fmt.Errorf("mode number must be 1-99")
	}
	return n, nil
}

func modePath(n int) string { return filepath.Join(configDir, fmt.Sprintf("mode%d.json", n)) }

func getModeJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, 405, apiReply{"ok": false, "error": "GET required"})
		return
	}
	if !tokenOK(r) {
		writeJSON(w, 403, apiReply{"ok": false, "error": "invalid token"})
		return
	}
	n, err := parseModeNumber(r)
	if err != nil {
		writeJSON(w, 400, apiReply{"ok": false, "error": err.Error()})
		return
	}
	b, err := os.ReadFile(modePath(n))
	if err != nil {
		if os.IsNotExist(err) {
			writeJSON(w, 404, apiReply{"ok": false, "error": "mode not found"})
			return
		}
		writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()})
		return
	}
	var obj any
	if json.Unmarshal(b, &obj) == nil {
		if pretty, err := json.MarshalIndent(obj, "", "  "); err == nil {
			b = pretty
		}
	}
	writeJSON(w, 200, apiReply{"ok": true, "number": n, "content": string(b)})
}

func saveModeJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
		return
	}
	if !tokenOK(r) {
		writeJSON(w, 403, apiReply{"ok": false, "error": "invalid token"})
		return
	}
	n, err := parseModeNumber(r)
	if err != nil {
		writeJSON(w, 400, apiReply{"ok": false, "error": err.Error()})
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxJSON)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, 400, apiReply{"ok": false, "error": "request body too large or unreadable"})
		return
	}
	body = []byte(strings.TrimSpace(string(body)))
	if len(body) == 0 || !json.Valid(body) {
		writeJSON(w, 400, apiReply{"ok": false, "error": "invalid JSON"})
		return
	}
	if err := os.MkdirAll(configDir, 0700); err != nil {
		writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()})
		return
	}
	tmp, err := os.CreateTemp(configDir, fmt.Sprintf(".mode%d-upload-*", n))
	if err != nil {
		writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()})
		return
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	_ = tmp.Chmod(0600)
	if _, err := tmp.Write(body); err != nil {
		_ = tmp.Close()
		writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()})
		return
	}
	_ = tmp.Sync()
	_ = tmp.Close()
	checkOut, err := exec.Command(singBox, "check", "-c", tmpPath).CombinedOutput()
	if err != nil {
		writeJSON(w, 400, apiReply{"ok": false, "error": "sing-box check failed", "details": strings.TrimSpace(string(checkOut))})
		return
	}
	dst := modePath(n)
	if old, err := os.ReadFile(dst); err == nil {
		_ = os.WriteFile(dst+".bak-web", old, 0600)
	}
	if err := os.Rename(tmpPath, dst); err != nil {
		writeJSON(w, 500, apiReply{"ok": false, "error": err.Error()})
		return
	}
	_ = os.Chmod(dst, 0600)
	writeJSON(w, 200, apiReply{"ok": true, "message": fmt.Sprintf("mode %d saved and validated", n)})
}

const page = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>U60 Proxy Mode</title><style>
*{box-sizing:border-box}body{margin:0;background:#0b0f14;color:#edf2f7;font-family:system-ui,-apple-system,Segoe UI,sans-serif}.wrap{max-width:1040px;margin:auto;padding:26px 18px 50px}header{display:flex;justify-content:space-between;align-items:flex-start;gap:16px}h1{margin:3px 0 4px;font-size:30px}.sub{color:#8ea0b5;font-size:13px}.badge{display:inline-flex;align-items:center;border-radius:999px;padding:6px 10px;font-size:12px;background:#1a2230;color:#cbd5e1}.ok{background:#12351f;color:#9be7b0}.bad{background:#3a1b1b;color:#f0aaaa}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:20px 0}.card,.panel{background:#111823;border:1px solid #202b3a;border-radius:15px}.card{padding:16px}.card span{display:block;color:#8ea0b5;font-size:12px;margin-bottom:7px}.card strong{font-size:17px}.panel{padding:18px;margin-top:14px}.panel h2{font-size:17px;margin:0 0 13px}.actions{display:flex;gap:9px;flex-wrap:wrap}button{border:1px solid #334155;background:#182231;color:#eef2f7;padding:9px 13px;border-radius:9px;font-weight:650;cursor:pointer}button.active{background:#17412a;border-color:#2e6c49;color:#aaf0bf}button:hover{background:#213047}.msg{color:#9fb0c3;font-size:13px;margin-top:12px}.client{display:flex;justify-content:space-between;gap:14px;align-items:center;padding:13px 0;border-top:1px solid #202b3a}.client:first-child{border-top:0}.meta{display:flex;flex-direction:column;gap:3px}.meta small{color:#8ea0b5}.policy{display:flex;gap:6px;align-items:center;flex-wrap:wrap}.pill{padding:4px 8px;border-radius:999px;font-size:11px;background:#1a2230}.pill.on{background:#12351f;color:#9be7b0}.pill.block{background:#3b2e12;color:#f4d27a}.modebar{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0 14px}.editor-head{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.editor-head input{width:90px}input,textarea{background:#0d141d;color:#eef2f7;border:1px solid #334155;border-radius:9px;padding:10px;font:inherit}textarea{width:100%;min-height:340px;margin-top:10px;font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px;line-height:1.45;resize:vertical}.hint{color:#7f91a7;font-size:12px;line-height:1.5;margin-top:8px}@media(max-width:720px){.grid{grid-template-columns:repeat(2,1fr)}.client{align-items:flex-start;flex-direction:column}}</style></head><body><div class="wrap"><header><div><div class="sub">ZTE U60 Pro</div><h1>Proxy Mode</h1><div class="sub">Per-device transparent proxy & leak protection</div></div><span id="state" class="badge">unknown</span></header>
<div class="grid"><div class="card"><span>Mode</span><strong id="mode">—</strong></div><div class="card"><span>Traffic</span><strong id="traffic">—</strong></div><div class="card"><span>DNS</span><strong id="dns">—</strong></div><div class="card"><span>IPv6 guard</span><strong id="v6">—</strong></div></div>
<div class="panel"><h2>Global control</h2><div class="actions"><button data-t="on">Proxy all</button><button data-t="off">Direct all</button><button data-t="selective">Per-device</button><button id="refresh">Refresh</button></div><div id="msg" class="msg">Ready.</div></div>
<div class="panel"><h2>Modes</h2><div id="modebar" class="modebar"></div><div class="editor-head"><label>Mode <input id="modeNumber" type="number" min="1" max="99" value="5"></label><button id="loadMode">Load selected</button><button id="activateMode">Activate selected</button><button id="saveMode">Validate & save</button><button id="saveStartMode">Save & activate</button></div><textarea id="modeJson" spellcheck="false" placeholder='Select a mode above to load its JSON, or paste a complete sing-box JSON configuration here'></textarea><div id="modeMsg" class="msg">Click a mode button to load its current JSON. Reading configs requires the control token because configs may contain credentials.</div><div class="hint">Save validates with sing-box first. Existing modeN.json is backed up as modeN.json.bak-web. Config contents stay on this device and are not sent to GitHub.</div></div>
<div class="panel"><h2>Connected devices</h2><div id="clients"></div><div class="msg">Proxy devices: TCP + DNS through proxy, UDP/QUIC blocked from bypass, global IPv6 blocked except proxied DNS. Direct devices keep native IPv4/IPv6.</div></div>
</div><script>
const $=id=>document.getElementById(id);
function tok(){let t=localStorage.getItem('u60ProxyToken')||'';if(!t){t=prompt('Enter control token')||'';if(t)localStorage.setItem('u60ProxyToken',t)}return t}
async function getj(p){let r=await fetch(p,{cache:'no-store'});if(!r.ok)throw Error('HTTP '+r.status);return r.json()}
async function authget(p){let t=tok();if(!t)throw Error('token required');let r=await fetch(p,{cache:'no-store',headers:{'X-Proxy-Token':t}});if(r.status===403)localStorage.removeItem('u60ProxyToken');let j=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.error||('HTTP '+r.status));return j}
async function post(p,body){let t=tok();if(!t)throw Error('token required');let r=await fetch(p,{method:'POST',headers:{'X-Proxy-Token':t,'Content-Type':'application/json'},body:body||''});if(r.status===403)localStorage.removeItem('u60ProxyToken');let j=await r.json().catch(()=>({}));if(!r.ok)throw Error((j.error||('HTTP '+r.status))+(j.details?' · '+j.details:''));return j}
function renderStatus(s){$('mode').textContent=s.mode||'—';$('traffic').textContent=s.traffic_mode||'off';$('dns').textContent=s.dns_proxy||'off';$('v6').textContent=s.ipv6_leak_guard||'off';$('state').textContent=s.state||'unknown';$('state').className='badge '+(s.state==='running'?'ok':'bad');document.querySelectorAll('[data-t]').forEach(b=>b.classList.toggle('active',b.dataset.t===(s.traffic_mode==='all'?'on':s.traffic_mode==='off'?'off':'selective')))}
function pills(c){if(c.policy==='proxy')return '<span class="pill on">Proxy</span><span class="pill on">DNS proxied</span><span class="pill block">IPv6 leak guard</span><span class="pill block">UDP/QUIC guard</span>';return '<span class="pill">Direct</span><span class="pill">Native IPv4/IPv6</span>'}
async function refreshModes(){try{let d=await getj('/api/modes'),box=$('modebar');box.innerHTML='';(d.modes||[]).forEach(m=>{let b=document.createElement('button');b.textContent='Mode '+m.number+(m.current?' · active':'');if(m.current)b.classList.add('active');b.onclick=()=>loadMode(m.number);box.appendChild(b)})}catch(e){$('modeMsg').textContent='Mode list failed: '+e.message}}
async function loadMode(n){n=n||parseInt($('modeNumber').value,10);if(!n)return;try{$('modeMsg').textContent='Loading mode '+n+'…';let j=await authget('/api/mode?number='+n);$('modeNumber').value=n;$('modeJson').value=j.content||'';$('modeMsg').textContent='Mode '+n+' loaded. Editing this text does not affect the running mode until you save/activate.'}catch(e){$('modeMsg').textContent='Load failed: '+e.message}}
async function refresh(){try{renderStatus(await getj('/api/status'));let d=await getj('/api/clients'),box=$('clients'),cs=d.clients||[];box.innerHTML=cs.length?'':'<div class="msg">No active IPv4 neighbors yet.</div>';cs.forEach(c=>{let row=document.createElement('div');row.className='client';row.innerHTML='<div class="meta"><strong>'+c.ip+'</strong><small>'+c.mac+' · '+c.state+'</small><div class="policy">'+pills(c)+'</div></div><div class="actions"><button class="'+(c.policy==='proxy'?'active':'')+'">Proxy</button><button class="'+(c.policy==='direct'?'active':'')+'">Direct</button></div>';let bs=row.querySelectorAll('button');bs[0].onclick=()=>dev(c.mac,'proxy');bs[1].onclick=()=>dev(c.mac,'direct');box.appendChild(row)});$('msg').textContent='Status updated.';await refreshModes()}catch(e){$('msg').textContent='Refresh failed: '+e.message}}
async function traffic(a){try{$('msg').textContent='Applying…';await post('/api/traffic?action='+encodeURIComponent(a));await refresh()}catch(e){$('msg').textContent='Action failed: '+e.message}}
async function dev(m,a){try{$('msg').textContent=m+' → '+a;await post('/api/device?selector='+encodeURIComponent(m)+'&action='+a);await refresh()}catch(e){$('msg').textContent='Action failed: '+e.message}}
async function saveMode(start){let n=parseInt($('modeNumber').value,10),body=$('modeJson').value.trim();if(!n||n<1||n>99){$('modeMsg').textContent='Mode number must be 1-99.';return}if(!body){$('modeMsg').textContent='Paste or load JSON first.';return}try{JSON.parse(body)}catch(e){$('modeMsg').textContent='Browser JSON check failed: '+e.message;return}try{$('modeMsg').textContent='Validating on U60…';let j=await post('/api/mode/save?number='+n,body);$('modeMsg').textContent=j.message;if(start)await activateMode(n);else{await refreshModes();await loadMode(n)}}catch(e){$('modeMsg').textContent='Save failed: '+e.message}}
async function activateMode(n){n=n||parseInt($('modeNumber').value,10);if(!n)return;try{$('modeMsg').textContent='Activating mode '+n+'…';let j=await post('/api/mode/activate?number='+n);$('modeMsg').textContent=j.message;await refresh()}catch(e){$('modeMsg').textContent='Activate failed: '+e.message}}
document.querySelectorAll('[data-t]').forEach(b=>b.onclick=()=>traffic(b.dataset.t));$('refresh').onclick=refresh;$('loadMode').onclick=()=>loadMode();$('activateMode').onclick=()=>activateMode();$('saveMode').onclick=()=>saveMode(false);$('saveStartMode').onclick=()=>saveMode(true);refresh();setInterval(refresh,15000);
</script></body></html>`

var tmpl = template.Must(template.New("page").Parse(page))

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_ = tmpl.Execute(w, nil)
	})
	mux.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, parseStatus()) })
	mux.HandleFunc("/api/clients", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, apiReply{"ok": true, "clients": clients()})
	})
	mux.HandleFunc("/api/modes", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, apiReply{"ok": true, "modes": listModes()})
	})
	mux.HandleFunc("/api/mode", getModeJSON)
	mux.HandleFunc("/api/mode/save", saveModeJSON)
	mux.HandleFunc("/api/mode/activate", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
			return
		}
		if !tokenOK(r) {
			writeJSON(w, 403, apiReply{"ok": false, "error": "invalid token"})
			return
		}
		n, err := parseModeNumber(r)
		if err != nil {
			writeJSON(w, 400, apiReply{"ok": false, "error": err.Error()})
			return
		}
		out, err := run("restart", strconv.Itoa(n))
		if err != nil {
			writeJSON(w, 500, apiReply{"ok": false, "error": out})
			return
		}
		writeJSON(w, 200, apiReply{"ok": true, "message": out})
	})
	mux.HandleFunc("/api/traffic", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
			return
		}
		if !tokenOK(r) {
			writeJSON(w, 403, apiReply{"ok": false, "error": "invalid token"})
			return
		}
		a := r.URL.Query().Get("action")
		if a != "on" && a != "off" && a != "selective" {
			writeJSON(w, 400, apiReply{"ok": false, "error": "invalid action"})
			return
		}
		out, err := run("traffic", a)
		if err != nil {
			writeJSON(w, 500, apiReply{"ok": false, "error": out})
			return
		}
		writeJSON(w, 200, apiReply{"ok": true, "message": out})
	})
	mux.HandleFunc("/api/device", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
			return
		}
		if !tokenOK(r) {
			writeJSON(w, 403, apiReply{"ok": false, "error": "invalid token"})
			return
		}
		m := strings.ToLower(r.URL.Query().Get("selector"))
		a := r.URL.Query().Get("action")
		if !macRE.MatchString(m) || (a != "proxy" && a != "direct") {
			writeJSON(w, 400, apiReply{"ok": false, "error": "invalid selector/action"})
			return
		}
		out, err := run("device", m, a)
		if err != nil {
			writeJSON(w, 500, apiReply{"ok": false, "error": out})
			return
		}
		writeJSON(w, 200, apiReply{"ok": true, "message": out})
	})
	s := &http.Server{Addr: listenAddr, Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second}
	log.Printf("u60-web listening on http://%s/", listenAddr)
	log.Fatal(s.ListenAndServe())
}
