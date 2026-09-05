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
	fullProxy  = "/data/proxy-mode/scripts/udp-tproxy.sh"
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

func runCmd(name string, args ...string) (string, error) {
	b, err := exec.Command(name, args...).CombinedOutput()
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

func parseStatus() statusData {
	out, err := run("status")
	if err != nil {
		return statusData{"state": "error", "error": out}
	}
	d := parseKV(out)
	if _, ok := d["udp_quic_guard"]; !ok {
		d["udp_quic_guard"] = "strict"
	}
	if v, ok := d["ipv6_guard"]; ok {
		d["ipv6_leak_guard"] = v
	}
	if _, ok := d["ipv6_leak_guard"]; !ok {
		d["ipv6_leak_guard"] = "unknown"
	}
	if out, err := runCmd(fullProxy, "status"); err == nil {
		for k, v := range parseKV(out) {
			d[k] = v
		}
	} else {
		d["full_proxy_udp"] = "unavailable"
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

func requireToken(w http.ResponseWriter, r *http.Request) bool {
	if tokenOK(r) {
		return true
	}
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
	st := parseStatus()
	proxySet, directSet := map[string]bool{}, map[string]bool{}
	for _, x := range strings.Fields(st["proxy_devices"]) {
		proxySet[strings.ToLower(strings.TrimPrefix(x, "mac:"))] = true
	}
	for _, x := range strings.Fields(st["direct_devices"]) {
		directSet[strings.ToLower(strings.TrimPrefix(x, "mac:"))] = true
	}
	list, seen := make([]client, 0), map[string]bool{}
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
	sort.Slice(list, func(i, j int) bool { return list[i].IP < list[j].IP })
	return list
}

func modeMeta(n int) (string, string) {
	switch n {
	case 4:
		return "VLESS Reality", "Stable · TCP + proxied DNS"
	case 5:
		return "SSH Direct", "SSH server as exit"
	case 6:
		return "SSH → SOCKS5", "Remote SOCKS5 through SSH"
	case 7:
		return "SSH Jump", "A jump host → B exit"
	case 8:
		return "LAN SOCKS5", "Use a SOCKS5 proxy on LAN"
	case 9:
		return "LAN HTTP", "Use an HTTP proxy on LAN"
	case 10:
		return "VLESS Full Proxy", "Experimental · TCP + UDP/XUDP"
	default:
		return fmt.Sprintf("Mode %d", n), "Custom sing-box configuration"
	}
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
		label, desc := modeMeta(n)
		out = append(out, modeInfo{Number: n, Name: e.Name(), Label: label, Description: desc, Current: current == m[1]})
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
	if !requireToken(w, r) {
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
	if !requireToken(w, r) {
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
	writeJSON(w, 200, apiReply{"ok": true, "message": fmt.Sprintf("Mode %d saved and validated", n)})
}

const page = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>U60 Proxy</title><style>
:root{color-scheme:dark;--bg:#091018;--panel:#101923;--panel2:#0d151e;--line:#223142;--muted:#8ea1b5;--text:#eef4fa;--green:#58d68d;--amber:#f5c451;--red:#ef7777;--blue:#70aefc}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 15% 0,#122132 0,transparent 35%),var(--bg);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif}.wrap{max-width:1120px;margin:auto;padding:30px 18px 60px}.top{display:flex;justify-content:space-between;gap:20px;align-items:center;margin-bottom:22px}.eyebrow{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.12em}.title{font-size:30px;font-weight:760;margin:4px 0}.subtitle{color:var(--muted);font-size:13px}.status-pill,.mini{border:1px solid var(--line);background:#15202c;border-radius:999px;padding:7px 11px;font-size:12px}.status-pill.ok,.mini.ok{color:#aaf0c4;border-color:#245c3a;background:#12321f}.status-pill.bad{color:#ffc1c1;border-color:#623333;background:#351a1a}.stats{display:grid;grid-template-columns:repeat(5,1fr);gap:10px}.stat,.panel{background:linear-gradient(180deg,#111c28,#0f1822);border:1px solid var(--line);border-radius:16px}.stat{padding:15px}.stat span{display:block;color:var(--muted);font-size:11px;margin-bottom:6px}.stat strong{font-size:16px}.panel{padding:18px;margin-top:14px}.panel-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;margin-bottom:14px}.panel h2{font-size:16px;margin:0}.panel-note{color:var(--muted);font-size:12px;margin-top:4px}.control-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}.control{padding:14px;background:var(--panel2);border:1px solid var(--line);border-radius:13px}.control-title{font-size:13px;font-weight:700;margin-bottom:8px}.control small{display:block;color:var(--muted);line-height:1.45;margin-bottom:10px}.actions{display:flex;gap:7px;flex-wrap:wrap}button{appearance:none;border:1px solid #32455b;background:#172331;color:var(--text);padding:8px 11px;border-radius:9px;font-weight:650;font-size:12px;cursor:pointer}button:hover{background:#1d2d3e}button.active{background:#153a27;border-color:#2e7650;color:#b7f4cb}button.warn{border-color:#6e5930;color:#f8d985}.mode-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.mode{padding:14px;text-align:left;border:1px solid var(--line);background:var(--panel2);border-radius:13px;cursor:pointer}.mode:hover{border-color:#3c566f}.mode.active{border-color:#36805a;background:#102b1d}.mode .num{font-size:11px;color:var(--muted)}.mode .name{font-size:14px;font-weight:750;margin:4px 0}.mode .desc{font-size:11px;color:var(--muted)}.client{display:grid;grid-template-columns:1fr auto;gap:14px;align-items:center;padding:13px 0;border-top:1px solid var(--line)}.client:first-child{border-top:0}.client strong{font-size:14px}.meta{color:var(--muted);font-size:11px;margin-top:3px}.tags{display:flex;gap:5px;flex-wrap:wrap;margin-top:7px}.tag{font-size:10px;border-radius:999px;padding:4px 7px;background:#172331;color:#b9c7d5}.tag.ok{background:#12321f;color:#aaf0c4}.tag.warn{background:#332811;color:#f6d982}.msg{font-size:12px;color:var(--muted);margin-top:10px;min-height:17px}details{margin-top:14px;border-top:1px solid var(--line);padding-top:14px}summary{cursor:pointer;font-weight:700;font-size:13px}.editorbar{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:12px}input,textarea{background:#09121b;color:var(--text);border:1px solid #304257;border-radius:9px;padding:9px;font:inherit}input{width:74px}textarea{width:100%;min-height:360px;margin-top:9px;resize:vertical;font:12px/1.45 ui-monospace,SFMono-Regular,Consolas,monospace}.experimental{border-color:#604d2b;background:linear-gradient(180deg,#1c1a13,#121820)}@media(max-width:850px){.stats{grid-template-columns:repeat(2,1fr)}.control-grid,.mode-grid{grid-template-columns:1fr 1fr}}@media(max-width:560px){.top{align-items:flex-start}.stats,.control-grid,.mode-grid{grid-template-columns:1fr}.client{grid-template-columns:1fr}.wrap{padding-top:20px}}
</style></head><body><div class="wrap">
<div class="top"><div><div class="eyebrow">ZTE U60 Pro</div><div class="title">Proxy Control</div><div class="subtitle">Transparent proxy · per-device policy · leak protection</div></div><span id="state" class="status-pill">Unknown</span></div>
<div class="stats"><div class="stat"><span>ACTIVE MODE</span><strong id="mode">—</strong></div><div class="stat"><span>TRAFFIC</span><strong id="traffic">—</strong></div><div class="stat"><span>DNS</span><strong id="dns">—</strong></div><div class="stat"><span>UDP</span><strong id="udp">—</strong></div><div class="stat"><span>IPV6</span><strong id="v6">—</strong></div></div>
<div class="panel"><div class="panel-head"><div><h2>Traffic & protection</h2><div class="panel-note">Common controls, separated by purpose.</div></div><button id="refresh">Refresh</button></div><div class="control-grid">
<div class="control"><div class="control-title">Client policy</div><small>Choose whether all devices, selected devices, or no devices use the proxy.</small><div class="actions"><button data-t="selective">Per-device</button><button data-t="on">Proxy all</button><button data-t="off">Direct all</button></div></div>
<div class="control"><div class="control-title">UDP / QUIC leak guard</div><small>Strict blocks UDP that is not handled by Full Proxy. Off allows native WAN UDP.</small><div class="actions"><button data-udp="strict">Strict</button><button data-udp="off">Off</button></div></div>
<div class="control"><div class="control-title">IPv6 leak guard</div><small>Strict blocks proxied clients from bypassing the IPv4 proxy over native IPv6.</small><div class="actions"><button data-v6="strict">Strict</button><button data-v6="off">Off</button></div></div>
</div><div id="msg" class="msg">Ready.</div></div>
<div class="panel experimental"><div class="panel-head"><div><h2>Full Proxy UDP <span class="mini" id="fullState">experimental</span></h2><div class="panel-note">Mode 10 experiment: TCP stays on REDIRECT :7893; UDP uses TPROXY :7894 and exits via VLESS/XUDP.</div></div></div><div class="actions"><button id="fullPreflight">Preflight</button><button id="fullApply" class="warn">Apply UDP TPROXY</button><button id="fullOff">Disable UDP TPROXY</button></div><div id="fullMsg" class="msg">Use only with a mode containing the UDP tproxy inbound on port 7894.</div></div>
<div class="panel"><div class="panel-head"><div><h2>Modes</h2><div class="panel-note">Click a card to load its JSON. Activation is always a separate action.</div></div></div><div id="modegrid" class="mode-grid"></div><details><summary>JSON editor</summary><div class="editorbar"><label>Mode <input id="modeNumber" type="number" min="1" max="99" value="4"></label><button id="loadMode">Load</button><button id="activateMode">Activate</button><button id="saveMode">Validate & save</button><button id="saveStartMode">Save & activate</button></div><textarea id="modeJson" spellcheck="false" placeholder="Select a mode card or paste a complete sing-box JSON configuration"></textarea><div id="modeMsg" class="msg">Config read/write requires the local control token.</div></details></div>
<div class="panel"><div class="panel-head"><div><h2>Connected devices</h2><div class="panel-note">Policy follows MAC address, so IPv4 and IPv6 handling stays tied to the same client.</div></div></div><div id="clients"></div></div>
</div><script>
const $=id=>document.getElementById(id);let lastStatus={};
function tok(){let t=localStorage.getItem('u60ProxyToken')||'';if(!t){t=prompt('Control token')||'';if(t)localStorage.setItem('u60ProxyToken',t)}return t}
async function getj(p){let r=await fetch(p,{cache:'no-store'});let j=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.error||('HTTP '+r.status));return j}
async function authget(p){let t=tok();if(!t)throw Error('token required');let r=await fetch(p,{cache:'no-store',headers:{'X-Proxy-Token':t}});if(r.status===403)localStorage.removeItem('u60ProxyToken');let j=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.error||('HTTP '+r.status));return j}
async function post(p,body=''){let t=tok();if(!t)throw Error('token required');let r=await fetch(p,{method:'POST',headers:{'X-Proxy-Token':t,'Content-Type':'application/json'},body});if(r.status===403)localStorage.removeItem('u60ProxyToken');let j=await r.json().catch(()=>({}));if(!r.ok)throw Error((j.error||('HTTP '+r.status))+(j.details?' · '+j.details:''));return j}
function pretty(v){return (v||'—').replaceAll('_',' ')}
function renderStatus(s){lastStatus=s;$('mode').textContent=s.mode&&s.mode!=='unconfigured'?'Mode '+s.mode:'Not configured';$('traffic').textContent=pretty(s.traffic_mode);$('dns').textContent=pretty(s.dns_proxy);$('udp').textContent=s.full_proxy_udp==='on'?'Full proxy':pretty(s.udp_quic_guard);$('v6').textContent=pretty(s.ipv6_leak_guard);$('state').textContent=s.state==='running'?'Engine running':'Engine '+(s.state||'unknown');$('state').className='status-pill '+(s.state==='running'?'ok':'bad');document.querySelectorAll('[data-t]').forEach(b=>b.classList.toggle('active',b.dataset.t===(s.traffic_mode==='all'?'on':s.traffic_mode==='off'?'off':'selective')));document.querySelectorAll('[data-udp]').forEach(b=>b.classList.toggle('active',b.dataset.udp===s.udp_quic_guard));document.querySelectorAll('[data-v6]').forEach(b=>b.classList.toggle('active',b.dataset.v6===s.ipv6_leak_guard));$('fullState').textContent=s.full_proxy_udp==='on'?'ON':'OFF';$('fullState').className='mini '+(s.full_proxy_udp==='on'?'ok':'')}
function tags(c){if(c.policy==='proxy'){let udp=lastStatus.full_proxy_udp==='on'?'<span class="tag ok">UDP full proxy</span>':(lastStatus.udp_quic_guard==='strict'?'<span class="tag warn">UDP blocked</span>':'<span class="tag warn">UDP direct</span>');return '<span class="tag ok">Proxy</span><span class="tag ok">DNS proxied</span>'+udp+'<span class="tag">IPv6 '+pretty(lastStatus.ipv6_leak_guard)+'</span>'}return '<span class="tag">Direct IPv4/IPv6</span>'}
async function refreshModes(){let d=await getj('/api/modes'),box=$('modegrid');box.innerHTML='';(d.modes||[]).forEach(m=>{let card=document.createElement('div');card.className='mode'+(m.current?' active':'');card.innerHTML='<div class="num">MODE '+m.number+(m.current?' · ACTIVE':'')+'</div><div class="name">'+esc(m.label||('Mode '+m.number))+'</div><div class="desc">'+esc(m.description||'')+'</div>';card.onclick=()=>loadMode(m.number);box.appendChild(card)})}
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
async function refresh(){try{let s=await getj('/api/status');renderStatus(s);let d=await getj('/api/clients'),box=$('clients'),cs=d.clients||[];box.innerHTML=cs.length?'':'<div class="msg">No active IPv4 neighbors.</div>';cs.forEach(c=>{let row=document.createElement('div');row.className='client';row.innerHTML='<div><strong>'+esc(c.ip||'Unknown IP')+'</strong><div class="meta">'+esc(c.mac||'Unknown MAC')+' · '+esc(c.state||'unknown')+'</div><div class="tags">'+tags(c)+'</div></div><div class="actions"><button data-a="proxy" class="'+(c.policy==='proxy'?'active':'')+'">Proxy</button><button data-a="direct" class="'+(c.policy==='direct'?'active':'')+'">Direct</button></div>';row.querySelector('[data-a=proxy]').onclick=()=>dev(c.mac,'proxy');row.querySelector('[data-a=direct]').onclick=()=>dev(c.mac,'direct');box.appendChild(row)});await refreshModes();$('msg').textContent='Updated.'}catch(e){$('msg').textContent='Refresh failed: '+e.message}}
async function traffic(a){try{$('msg').textContent='Applying…';await post('/api/traffic?action='+a);await refresh()}catch(e){$('msg').textContent='Action failed: '+e.message}}
async function guard(kind,val){try{$('msg').textContent='Applying '+kind+' guard…';await post('/api/guard?kind='+kind+'&value='+val);await refresh()}catch(e){$('msg').textContent='Guard failed: '+e.message}}
async function dev(mac,a){try{await post('/api/device?selector='+encodeURIComponent(mac)+'&action='+a);await refresh()}catch(e){$('msg').textContent='Device action failed: '+e.message}}
async function loadMode(n){n=n||parseInt($('modeNumber').value,10);if(!n)return;try{$('modeMsg').textContent='Loading Mode '+n+'…';let j=await authget('/api/mode?number='+n);$('modeNumber').value=n;$('modeJson').value=j.content||'';$('modeMsg').textContent='Mode '+n+' loaded. Nothing changes until save/activate.';$('modeJson').closest('details').open=true}catch(e){$('modeMsg').textContent='Load failed: '+e.message}}
async function saveMode(start){let n=parseInt($('modeNumber').value,10),body=$('modeJson').value.trim();if(!body){$('modeMsg').textContent='Load or paste JSON first.';return}try{JSON.parse(body)}catch(e){$('modeMsg').textContent='JSON error: '+e.message;return}try{$('modeMsg').textContent='Validating on U60…';let j=await post('/api/mode/save?number='+n,body);$('modeMsg').textContent=j.message;if(start)await activateMode(n);else await refreshModes()}catch(e){$('modeMsg').textContent='Save failed: '+e.message}}
async function activateMode(n){n=n||parseInt($('modeNumber').value,10);try{$('modeMsg').textContent='Activating Mode '+n+'…';let j=await post('/api/mode/activate?number='+n);$('modeMsg').textContent=j.message;await refresh()}catch(e){$('modeMsg').textContent='Activate failed: '+e.message}}
async function fp(a){try{$('fullMsg').textContent='Running '+a+'…';let j=await post('/api/fullproxy?action='+a);$('fullMsg').textContent=j.message||'Done';await refresh()}catch(e){$('fullMsg').textContent='Full Proxy: '+e.message}}
document.querySelectorAll('[data-t]').forEach(b=>b.onclick=()=>traffic(b.dataset.t));document.querySelectorAll('[data-udp]').forEach(b=>b.onclick=()=>guard('udp',b.dataset.udp));document.querySelectorAll('[data-v6]').forEach(b=>b.onclick=()=>guard('ipv6',b.dataset.v6));$('refresh').onclick=refresh;$('loadMode').onclick=()=>loadMode();$('activateMode').onclick=()=>activateMode();$('saveMode').onclick=()=>saveMode(false);$('saveStartMode').onclick=()=>saveMode(true);$('fullPreflight').onclick=()=>fp('preflight');$('fullApply').onclick=()=>fp('apply');$('fullOff').onclick=()=>fp('off');refresh();setInterval(refresh,15000);
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
	mux.HandleFunc("/api/clients", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, apiReply{"ok": true, "clients": clients()}) })
	mux.HandleFunc("/api/modes", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, apiReply{"ok": true, "modes": listModes()}) })
	mux.HandleFunc("/api/mode", getModeJSON)
	mux.HandleFunc("/api/mode/save", saveModeJSON)
	mux.HandleFunc("/api/mode/activate", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
			return
		}
		if !requireToken(w, r) {
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
		if !requireToken(w, r) {
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
	mux.HandleFunc("/api/guard", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
			return
		}
		if !requireToken(w, r) {
			return
		}
		kind, val := r.URL.Query().Get("kind"), r.URL.Query().Get("value")
		if (kind != "udp" && kind != "ipv6") || (val != "strict" && val != "off") {
			writeJSON(w, 400, apiReply{"ok": false, "error": "invalid guard"})
			return
		}
		out, err := run("guard", kind, val)
		if err != nil {
			writeJSON(w, 500, apiReply{"ok": false, "error": out})
			return
		}
		writeJSON(w, 200, apiReply{"ok": true, "message": out})
	})
	mux.HandleFunc("/api/fullproxy", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, apiReply{"ok": false, "error": "POST required"})
			return
		}
		if !requireToken(w, r) {
			return
		}
		a := r.URL.Query().Get("action")
		if a != "preflight" && a != "apply" && a != "off" {
			writeJSON(w, 400, apiReply{"ok": false, "error": "invalid action"})
			return
		}
		out, err := runCmd(fullProxy, a)
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
		if !requireToken(w, r) {
			return
		}
		m, a := strings.ToLower(r.URL.Query().Get("selector")), r.URL.Query().Get("action")
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
