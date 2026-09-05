package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	base       = "/data/u60proxy"
	stateDir   = base + "/state"
	runtimeDir = base + "/runtime"
	deviceFile = stateDir + "/devices.json"
	modeFile   = stateDir + "/current_mode"
	oldBase    = "/data/proxy-mode"
)

var mu sync.Mutex

type Policy struct {
	Name  string `json:"name"`
	Proxy bool   `json:"proxy"`
	DNS   bool   `json:"dns"`
	UDP   bool   `json:"udp"`
	IPv6  bool   `json:"ipv6"`
}

type Device struct {
	MAC    string `json:"mac"`
	IP     string `json:"ip"`
	Name   string `json:"name"`
	Proxy  bool   `json:"proxy"`
	DNS    bool   `json:"dns"`
	UDP    bool   `json:"udp"`
	IPv6   bool   `json:"ipv6"`
	Online bool   `json:"online"`
}

type Mode struct {
	ID         int    `json:"id"`
	Name       string `json:"name"`
	UDP        bool   `json:"udp"`
	Deprecated bool   `json:"deprecated"`
}

func ensure() error {
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(runtimeDir, 0755); err != nil {
		return err
	}
	if _, e := os.Stat(deviceFile); os.IsNotExist(e) {
		if err := savePolicies(map[string]Policy{}); err != nil {
			return err
		}
	}
	if _, e := os.Stat(modeFile); os.IsNotExist(e) {
		_ = os.WriteFile(modeFile, []byte("11\n"), 0644)
	}
	return nil
}
func normMAC(s string) string { return strings.ToLower(strings.TrimSpace(s)) }
func loadPolicies() (map[string]Policy, error) {
	b, e := os.ReadFile(deviceFile)
	if e != nil {
		return nil, e
	}
	var p map[string]Policy
	if len(strings.TrimSpace(string(b))) == 0 {
		return map[string]Policy{}, nil
	}
	if e = json.Unmarshal(b, &p); e != nil {
		return nil, e
	}
	if p == nil {
		p = map[string]Policy{}
	}
	return p, nil
}
func savePolicies(p map[string]Policy) error {
	b, e := json.MarshalIndent(p, "", "  ")
	if e != nil {
		return e
	}
	b = append(b, '\n')
	return atomicWrite(deviceFile, b, 0644)
}
func atomicWrite(path string, b []byte, mode os.FileMode) error {
	tmp := path + ".tmp"
	if e := os.WriteFile(tmp, b, mode); e != nil {
		return e
	}
	return os.Rename(tmp, path)
}

func leases() map[string]Device {
	out := map[string]Device{}
	b, e := os.ReadFile("/tmp/dhcp.leases")
	if e != nil {
		return out
	}
	for _, ln := range strings.Split(string(b), "\n") {
		f := strings.Fields(ln)
		if len(f) < 4 {
			continue
		}
		mac := normMAC(f[1])
		name := f[3]
		if name == "*" {
			name = "Unknown"
		}
		out[mac] = Device{MAC: mac, IP: f[2], Name: name}
	}
	return out
}

func neighbors() map[string]string {
	out := map[string]string{}
	b, e := exec.Command("ip", "neigh", "show", "dev", "br-lan").Output()
	if e != nil {
		return out
	}
	for _, ln := range strings.Split(string(b), "\n") {
		f := strings.Fields(ln)
		if len(f) < 5 {
			continue
		}
		state := strings.ToUpper(f[len(f)-1])
		if state == "FAILED" || state == "INCOMPLETE" {
			continue
		}
		for i := 0; i+1 < len(f); i++ {
			if f[i] == "lladdr" {
				mac := normMAC(f[i+1])
				out[mac] = f[0]
				break
			}
		}
	}
	return out
}

func associatedMACs() map[string]bool {
	out := map[string]bool{}
	for _, ifn := range []string{"wlan0", "wlan2", "wlan1", "wlan3"} {
		b, e := exec.Command("iw", "dev", ifn, "station", "dump").Output()
		if e != nil {
			continue
		}
		for _, ln := range strings.Split(string(b), "\n") {
			f := strings.Fields(ln)
			if len(f) >= 2 && f[0] == "Station" {
				out[normMAC(f[1])] = true
			}
		}
	}
	return out
}
func scan() error {
	mu.Lock()
	defer mu.Unlock()
	if e := ensure(); e != nil {
		return e
	}
	p, e := loadPolicies()
	if e != nil {
		return e
	}
	for mac, d := range leases() {
		q, ok := p[mac]
		if !ok {
			q = Policy{Name: d.Name}
		} else if d.Name != "" && d.Name != "Unknown" {
			q.Name = d.Name
		}
		p[mac] = q
	}
	return savePolicies(p)
}
func devices() ([]Device, error) {
	if e := scan(); e != nil {
		return nil, e
	}
	p, e := loadPolicies()
	if e != nil {
		return nil, e
	}
	ls := leases()
	ng := neighbors()
	assoc := associatedMACs()
	out := make([]Device, 0, len(p))
	for mac, q := range p {
		d := Device{MAC: mac, Name: q.Name, Proxy: q.Proxy, DNS: q.DNS, UDP: q.UDP, IPv6: q.IPv6}
		if l, ok := ls[mac]; ok {
			d.IP = l.IP
			if d.Name == "" || d.Name == "Unknown" {
				d.Name = l.Name
			}
		}
		if ip, ok := ng[mac]; ok {
			d.Online = true
			if d.IP == "" || strings.Contains(d.IP, ":") {
				d.IP = ip
			}
		}
		if assoc[mac] {
			d.Online = true
		}
		out = append(out, d)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Online != out[j].Online {
			return out[i].Online
		}
		return out[i].Name < out[j].Name
	})
	return out, nil
}
func setDevice(mac, field string, val bool) error {
	mac = normMAC(mac)
	ok, _ := regexp.MatchString(`^([0-9a-f]{2}:){5}[0-9a-f]{2}$`, mac)
	if !ok {
		return fmt.Errorf("invalid MAC")
	}
	mu.Lock()
	defer mu.Unlock()
	p, e := loadPolicies()
	if e != nil {
		return e
	}
	q := p[mac]
	if q.Name == "" {
		if l, ok := leases()[mac]; ok {
			q.Name = l.Name
		}
	}
	switch field {
	case "proxy":
		q.Proxy = val
	case "dns":
		q.DNS = val
	case "udp":
		q.UDP = val
	case "ipv6":
		q.IPv6 = val
	default:
		return fmt.Errorf("invalid field")
	}
	p[mac] = q
	if e = savePolicies(p); e != nil {
		return e
	}
	return applyLocked(p)
}
func setPreset(mac, preset string) error {
	mac = normMAC(mac)
	ok, _ := regexp.MatchString(`^([0-9a-f]{2}:){5}[0-9a-f]{2}$`, mac)
	if !ok {
		return fmt.Errorf("invalid MAC")
	}
	mu.Lock()
	defer mu.Unlock()
	p, e := loadPolicies()
	if e != nil {
		return e
	}
	q := p[mac]
	if q.Name == "" {
		if l, ok := leases()[mac]; ok {
			q.Name = l.Name
		}
	}
	switch preset {
	case "full":
		q.Proxy, q.DNS, q.UDP, q.IPv6 = true, true, true, true
	case "direct":
		q.Proxy, q.DNS, q.UDP, q.IPv6 = false, false, false, false
	default:
		return fmt.Errorf("invalid preset")
	}
	p[mac] = q
	if e = savePolicies(p); e != nil {
		return e
	}
	return applyLocked(p)
}

func writeList(name string, p map[string]Policy, pred func(Policy) bool) error {
	var a []string
	for mac, q := range p {
		if pred(q) {
			a = append(a, "mac:"+mac)
		}
	}
	sort.Strings(a)
	s := ""
	if len(a) > 0 {
		s = strings.Join(a, "\n") + "\n"
	}
	if e := atomicWrite(filepath.Join(runtimeDir, name), []byte(s), 0644); e != nil {
		return e
	}
	_ = os.MkdirAll(oldBase+"/runtime", 0755)
	return atomicWrite(filepath.Join(oldBase, "runtime", name), []byte(s), 0644)
}
func run(path string, args ...string) error {
	c := exec.Command(path, args...)
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return c.Run()
}
func applyLocked(p map[string]Policy) error {
	if e := writeList("proxy_devices", p, func(q Policy) bool { return q.Proxy }); e != nil {
		return e
	}
	if e := writeList("dns_devices", p, func(q Policy) bool { return q.DNS }); e != nil {
		return e
	}
	if e := writeList("udp_devices", p, func(q Policy) bool { return q.UDP }); e != nil {
		return e
	}
	if e := writeList("ipv6_devices", p, func(q Policy) bool { return q.IPv6 }); e != nil {
		return e
	}
	_ = os.WriteFile(oldBase+"/runtime/traffic_mode", []byte("selective\n"), 0644)
	if _, e := os.Stat(oldBase + "/scripts/traffic.sh"); e == nil {
		if e = run(oldBase+"/scripts/traffic.sh", "apply"); e != nil {
			return e
		}
	}
	m := currentMode()
	if m == 11 {
		if _, e := os.Stat("/sys/class/net/u60udp0"); e == nil {
			_ = run(oldBase+"/scripts/udp-tun.sh", "apply")
		}
	} else {
		_ = run(oldBase+"/scripts/udp-tun.sh", "off")
	}
	return nil
}
func apply() error {
	mu.Lock()
	defer mu.Unlock()
	p, e := loadPolicies()
	if e != nil {
		return e
	}
	return applyLocked(p)
}
func currentMode() int {
	b, e := os.ReadFile(modeFile)
	if e != nil {
		return 11
	}
	n, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	if n == 0 {
		return 11
	}
	return n
}
func setMode(n int) error {
	if n == 10 {
		return fmt.Errorf("mode 10 is deprecated")
	}
	if n < 1 || n > 99 {
		return fmt.Errorf("invalid mode")
	}
	if e := os.WriteFile(modeFile, []byte(fmt.Sprintf("%d\n", n)), 0644); e != nil {
		return e
	}
	if e := run(oldBase+"/bin/proxy-mode", "restart", strconv.Itoa(n)); e != nil {
		return e
	}
	time.Sleep(1200 * time.Millisecond)
	return apply()
}
func modeList() []Mode {
	meta := map[int]Mode{
		4:  {4, "VLESS Reality", false, false},
		5:  {5, "SSH Direct", false, false},
		6:  {6, "SSH → SOCKS5", false, false},
		7:  {7, "SSH Jump", false, false},
		8:  {8, "LAN SOCKS5", false, false},
		9:  {9, "LAN HTTP", false, false},
		10: {10, "VLESS TPROXY", true, true},
		11: {11, "VLESS Full Proxy", true, false},
	}
	paths, _ := filepath.Glob(oldBase + "/configs/mode*.json")
	seen := map[int]bool{}
	var out []Mode
	re := regexp.MustCompile(`mode([0-9]+)\.json$`)
	for _, path := range paths {
		m := re.FindStringSubmatch(path)
		if len(m) != 2 {
			continue
		}
		id, err := strconv.Atoi(m[1])
		if err != nil || id < 1 || id > 99 || seen[id] {
			continue
		}
		seen[id] = true
		md, ok := meta[id]
		if !ok {
			md = Mode{ID: id, Name: fmt.Sprintf("Custom Mode %d", id)}
		}
		out = append(out, md)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}
func migrate() error {
	if e := scan(); e != nil {
		return e
	}
	mu.Lock()
	defer mu.Unlock()
	p, e := loadPolicies()
	if e != nil {
		return e
	}
	b, _ := os.ReadFile(oldBase + "/runtime/proxy_devices")
	for _, ln := range strings.Split(string(b), "\n") {
		ln = strings.TrimSpace(ln)
		if strings.HasPrefix(ln, "mac:") {
			mac := normMAC(strings.TrimPrefix(ln, "mac:"))
			q := p[mac]
			if q.Name == "" {
				if l, ok := leases()[mac]; ok {
					q.Name = l.Name
				}
			}
			q.Proxy, q.DNS, q.UDP, q.IPv6 = true, true, true, true
			p[mac] = q
		}
	}
	return savePolicies(p)
}

func wanMode() string {
	if _, e := os.Stat("/sys/class/net/rmnet_data0"); e == nil {
		return "SIM"
	}
	return "UNKNOWN"
}
func statusMap() map[string]any {
	ds, _ := devices()
	online := 0
	for _, d := range ds {
		if d.Online {
			online++
		}
	}
	m := currentMode()
	return map[string]any{"version": "2.1.1", "wan": wanMode(), "mode": m, "online": online, "devices": ds}
}
func jsonResp(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}
func api(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/api/status":
		jsonResp(w, statusMap())
	case "/api/devices":
		d, e := devices()
		if e != nil {
			http.Error(w, e.Error(), 500)
			return
		}
		jsonResp(w, d)
	case "/api/modes":
		jsonResp(w, modeList())
	case "/api/device/set":
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		v := r.URL.Query().Get("value") == "on"
		if e := setDevice(r.URL.Query().Get("mac"), r.URL.Query().Get("field"), v); e != nil {
			http.Error(w, e.Error(), 400)
			return
		}
		jsonResp(w, map[string]any{"ok": true})
	case "/api/device/preset":
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		if e := setPreset(r.URL.Query().Get("mac"), r.URL.Query().Get("preset")); e != nil {
			http.Error(w, e.Error(), 400)
			return
		}
		jsonResp(w, map[string]any{"ok": true})
	case "/api/mode/set":
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		n, _ := strconv.Atoi(r.URL.Query().Get("mode"))
		if e := setMode(n); e != nil {
			http.Error(w, e.Error(), 400)
			return
		}
		jsonResp(w, map[string]any{"ok": true})
	case "/api/apply":
		if r.Method != http.MethodPost {
			http.Error(w, "POST required", 405)
			return
		}
		if e := apply(); e != nil {
			http.Error(w, e.Error(), 500)
			return
		}
		jsonResp(w, map[string]any{"ok": true})
	default:
		http.NotFound(w, r)
	}
}

const page = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>U60 Proxy</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 15% -10%,#1d3147 0,#0a0f16 34%,#070b10 72%);color:#edf4ff;font:14px system-ui,-apple-system,Segoe UI,Roboto,sans-serif;min-height:100vh}.wrap{max-width:1100px;margin:auto;padding:22px}.panel{background:rgba(16,24,34,.88);border:1px solid #28384a;border-radius:18px;box-shadow:0 14px 40px rgba(0,0,0,.24);backdrop-filter:blur(12px)}.hero{padding:20px;display:grid;grid-template-columns:1fr auto;gap:18px;align-items:center}.title{font-size:25px;font-weight:800;letter-spacing:.2px}.sub{color:#8fa3bb;margin-top:5px}.stats{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}.chip{display:inline-flex;align-items:center;gap:7px;padding:7px 10px;border:1px solid #33465b;border-radius:999px;background:#162231;color:#dce9f8}.dot{width:8px;height:8px;border-radius:50%;background:#5d6b7b}.dot.ok{background:#49d39a;box-shadow:0 0 0 4px rgba(73,211,154,.1)}.section{margin-top:14px;padding:17px}.section-head{display:flex;justify-content:space-between;align-items:center;gap:12px}.section-title{font-size:16px;font-weight:750}.muted{color:#8fa3bb}.modes{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.mode{border:1px solid #33465b;background:#131d29;color:#dce9f8;padding:10px 12px;border-radius:12px;cursor:pointer;transition:.16s transform,.16s border,.16s background}.mode:hover{transform:translateY(-1px);border-color:#5b7694}.mode.active{background:#eaf2fb;color:#091018;border-color:#eaf2fb}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(315px,1fr));gap:12px;margin-top:14px}.device{padding:16px;position:relative;overflow:hidden}.device.online:before{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:#49d39a}.dtop{display:flex;justify-content:space-between;gap:12px}.name{font-size:18px;font-weight:760}.meta{color:#8fa3bb;font-size:12px;margin-top:3px;word-break:break-all}.state{font-size:11px;font-weight:700;letter-spacing:.5px;padding:6px 8px;border-radius:999px;border:1px solid #3b4a5c;color:#94a5b9;height:max-content}.state.on{color:#62dda9;border-color:#285a48;background:#10261f}.quick{display:flex;gap:7px;margin-top:13px}.quick button{flex:1}.switches{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin-top:10px}.sw,.quick button{border:1px solid #34465a;background:#121c27;color:#cbd8e7;padding:10px;border-radius:11px;cursor:pointer;transition:.15s}.sw:hover,.quick button:hover{border-color:#5b7694}.sw.on{background:#eaf2fb;color:#091018;border-color:#eaf2fb;font-weight:700}.sw.busy,.quick button.busy{opacity:.55;pointer-events:none}.label{display:flex;align-items:center;justify-content:space-between;gap:8px}.pill{font-size:10px;padding:3px 6px;border-radius:999px;background:rgba(255,255,255,.08)}.toolbar{display:flex;align-items:center;gap:8px}.refresh{border:1px solid #34465a;background:#121c27;color:#dce9f8;border-radius:10px;padding:8px 10px;cursor:pointer}.refresh.spin{animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}#toast{position:fixed;right:20px;bottom:20px;background:#eaf2fb;color:#091018;padding:11px 14px;border-radius:12px;font-weight:700;box-shadow:0 12px 28px rgba(0,0,0,.35);opacity:0;transform:translateY(8px);pointer-events:none;transition:.2s}#toast.show{opacity:1;transform:none}.foot{color:#71869e;text-align:center;margin:18px 0 6px;font-size:12px}@media(max-width:640px){.wrap{padding:12px}.hero{grid-template-columns:1fr}.stats{justify-content:flex-start}.grid{grid-template-columns:1fr}.section-head{align-items:flex-start}.switches{grid-template-columns:1fr 1fr}}</style></head><body><div class="wrap"><div class="panel hero"><div><div class="title">U60 Proxy</div><div class="sub">设备级透明代理控制 · 实时在线检测</div></div><div id="summary" class="stats"></div></div><div class="panel section"><div class="section-head"><div><div class="section-title">Proxy Mode</div><div class="muted" id="modeHint">正在读取状态…</div></div><div class="toolbar"><span class="muted" id="updated"></span><button class="refresh" id="refresh" onclick="load(true)">↻</button></div></div><div id="modes" class="modes"></div></div><div id="devices" class="grid"></div><div class="foot">U60 Proxy v2.1.1 · Wi-Fi Relay not included</div></div><div id="toast"></div><script>
let busy=new Set(), timer; async function j(u,o){let r=await fetch(u,o);if(!r.ok)throw new Error((await r.text()).trim()||('HTTP '+r.status));return r.json()}function esc(s){return String(s??'').replace(/[&<>\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[c]))}function toast(t){let x=document.getElementById('toast');x.textContent=t;x.classList.add('show');clearTimeout(x._t);x._t=setTimeout(()=>x.classList.remove('show'),1800)}function chip(t,ok){return '<span class="chip"><span class="dot '+(ok?'ok':'')+'"></span>'+esc(t)+'</span>'}async function load(manual=false){let rb=document.getElementById('refresh');if(manual)rb.classList.add('spin');try{let [s,m,d]=await Promise.all([j('/api/status'),j('/api/modes'),j('/api/devices')]);summary.innerHTML=chip('WAN '+s.wan,s.wan==='SIM')+chip('Mode '+s.mode,true)+chip((s.online||0)+' online',(s.online||0)>0);modeHint.textContent=s.mode===11?'Mode 11 · TCP REDIRECT + UDP TUN/XUDP':'当前模式 '+s.mode;modes.innerHTML=m.filter(x=>!x.deprecated).map(x=>'<button class="mode '+(x.id==s.mode?'active':'')+'" onclick="mode('+x.id+')">'+x.id+' · '+esc(x.name)+(x.udp?' · UDP':'')+'</button>').join('');devices.innerHTML=d.map(card).join('')||'<div class="panel device">暂无已记录设备</div>';updated.textContent=new Date().toLocaleTimeString();}catch(e){toast(e.message)}finally{rb.classList.remove('spin')}}function card(x){let key=x.mac;let b=busy.has(key);return '<div class="panel device '+(x.online?'online':'')+'"><div class="dtop"><div><div class="name">'+esc(x.name||'Unknown')+'</div><div class="meta">'+esc(x.ip||'暂无 IP')+' · '+esc(x.mac)+'</div></div><span class="state '+(x.online?'on':'')+'">'+(x.online?'ONLINE':'OFFLINE')+'</span></div><div class="quick"><button class="'+(b?'busy':'')+'" onclick="preset(\''+key+'\',\'full\')">⚡ 全代理</button><button class="'+(b?'busy':'')+'" onclick="preset(\''+key+'\',\'direct\')">○ 全直连</button></div><div class="switches">'+sw(x,'proxy','TCP')+sw(x,'dns','DNS')+sw(x,'udp','UDP')+sw(x,'ipv6','IPv6 Guard')+'</div></div>'}function sw(x,f,n){let b=busy.has(x.mac);return '<button class="sw '+(x[f]?'on ':'')+(b?'busy':'')+'" onclick="setd(\''+x.mac+'\',\''+f+'\','+(!x[f])+')"><span class="label"><span>'+n+'</span><span class="pill">'+(x[f]?'ON':'OFF')+'</span></span></button>'}async function act(mac,fn,msg){busy.add(mac);await load();try{await fn();toast(msg)}catch(e){toast(e.message)}finally{busy.delete(mac);await load()}}async function setd(mac,f,v){await act(mac,()=>j('/api/device/set?mac='+encodeURIComponent(mac)+'&field='+f+'&value='+(v?'on':'off'),{method:'POST'}),f.toUpperCase()+' '+(v?'已开启':'已关闭'))}async function preset(mac,p){await act(mac,()=>j('/api/device/preset?mac='+encodeURIComponent(mac)+'&preset='+p,{method:'POST'}),p==='full'?'已切换全代理':'已切换全直连')}async function mode(n){if(!confirm('切换到 Mode '+n+'？'))return;try{toast('正在切换 Mode '+n+'…');await j('/api/mode/set?mode='+n,{method:'POST'});toast('Mode '+n+' 已启用');await load()}catch(e){toast(e.message)}}load();timer=setInterval(()=>{if(busy.size===0)load()},3000)
</script></body></html>`

func serve() {
	if e := ensure(); e != nil {
		panic(e)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/", api)
	t := template.Must(template.New("p").Parse(page))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = t.Execute(w, nil)
	})
	s := &http.Server{Addr: "10.66.0.1:8081", Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	fmt.Println("u60proxy v2 web: http://10.66.0.1:8081")
	if e := s.ListenAndServe(); e != nil && e != http.ErrServerClosed {
		panic(e)
	}
}

func usage() {
	fmt.Println(`u60proxy v2
  u60proxy serve
  u60proxy status
  u60proxy scan
  u60proxy apply
  u60proxy migrate
  u60proxy devices
  u60proxy device <MAC> <proxy|dns|udp|ipv6> <on|off>
  u60proxy mode list|get|set <ID>
  u60proxy doctor
  u60proxy backup
  u60proxy rollback [BACKUP_DIR|latest]`)
}
func main() {
	if e := ensure(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
	if len(os.Args) < 2 {
		usage()
		return
	}
	var e error
	switch os.Args[1] {
	case "serve":
		serve()
		return
	case "status":
		b, _ := json.MarshalIndent(statusMap(), "", "  ")
		fmt.Println(string(b))
	case "scan":
		e = scan()
	case "apply":
		e = apply()
	case "migrate":
		e = migrate()
	case "devices":
		d, x := devices()
		e = x
		b, _ := json.MarshalIndent(d, "", "  ")
		fmt.Println(string(b))
	case "device":
		if len(os.Args) != 5 {
			usage()
			os.Exit(2)
		}
		e = setDevice(os.Args[2], os.Args[3], os.Args[4] == "on")
	case "mode":
		if len(os.Args) < 3 {
			usage()
			os.Exit(2)
		}
		switch os.Args[2] {
		case "list":
			b, _ := json.MarshalIndent(modeList(), "", "  ")
			fmt.Println(string(b))
		case "get":
			fmt.Println(currentMode())
		case "set":
			if len(os.Args) != 4 {
				usage()
				os.Exit(2)
			}
			n, _ := strconv.Atoi(os.Args[3])
			e = setMode(n)
		default:
			usage()
		}
	case "doctor":
		e = run(base + "/bin/u60doctor")
	case "backup":
		e = run(base + "/bin/u60backup")
	case "rollback":
		arg := "latest"
		if len(os.Args) >= 3 {
			arg = os.Args[2]
		}
		e = run(base+"/bin/u60rollback", arg)
	default:
		usage()
	}
	if e != nil {
		fmt.Fprintln(os.Stderr, "error:", e)
		os.Exit(1)
	}
	_ = io.Discard
}
