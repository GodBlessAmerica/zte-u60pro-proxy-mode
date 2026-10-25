package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// Transform locally; no production config or credentials are uploaded to GitHub.
func transform(data []byte) ([]byte, error) {
	var c map[string]any
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, err
	}
	outs, _ := c["outbounds"].([]any)
	if len(outs) == 0 {
		return nil, fmt.Errorf("missing outbounds")
	}
	o, _ := outs[0].(map[string]any)
	route, _ := c["route"].(map[string]any)
	tag, _ := o["tag"].(string)
	if o["type"] != "vless" || tag == "" || route == nil || route["final"] != tag {
		return nil, fmt.Errorf("Mode 11 must use its first VLESS outbound as route.final")
	}
	ins, _ := c["inbounds"].([]any)
	foundTun, foundTCP := false, false
	for _, v := range ins {
		ib, ok := v.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("invalid inbound")
		}
		if ib["tag"] == "vless6-redirect-in" {
			if ib["type"] != "redirect" || ib["listen"] != "::" || ib["listen_port"] != float64(7894) {
				return nil, fmt.Errorf("reserved IPv6 inlet tag conflicts")
			}
			foundTCP = true
		} else if ib["listen_port"] == float64(7894) {
			return nil, fmt.Errorf("port 7894 already used by another inbound")
		}
		if ib["type"] == "tun" && ib["interface_name"] == "u60udp0" {
			if foundTun {
				return nil, fmt.Errorf("multiple u60udp0 TUN inbounds")
			}
			foundTun = true
			addresses, ok := ib["address"].([]any)
			if !ok {
				return nil, fmt.Errorf("TUN address must be an array")
			}
			has := false
			for _, a := range addresses {
				if a == "fd75:60:0:168::1/126" {
					has = true
				}
			}
			if !has {
				ib["address"] = append(addresses, "fd75:60:0:168::1/126")
			}
			if ib["auto_route"] == true {
				return nil, fmt.Errorf("existing u60udp0 must use auto_route=false")
			}
		}
	}
	if !foundTun {
		return nil, fmt.Errorf("Mode 11 has no u60udp0 TUN; use a full-proxy VLESS config first")
	}
	if !foundTCP {
		ins = append(ins, map[string]any{"type": "redirect", "tag": "vless6-redirect-in", "listen": "::", "listen_port": 7894})
	}
	c["inbounds"] = ins
	dns, ok := c["dns"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("missing DNS config")
	}
	dns["strategy"] = "prefer_ipv6"
	rules, _ := route["rules"].([]any)
	// Replace our dedicated rule so repeated updates are idempotent.
	kept := []any{map[string]any{"inbound": []string{"vless6-redirect-in"}, "action": "route", "outbound": tag}}
	for _, v := range rules {
		r, ok := v.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("invalid route rule")
		}
		a, ok := r["inbound"].([]any)
		if ok && len(a) == 1 && a[0] == "vless6-redirect-in" {
			continue
		}
		kept = append(kept, v)
	}
	route["rules"] = kept
	b, err := json.MarshalIndent(c, "", "  ")
	return append(b, '\n'), err
}

func run() error {
	if len(os.Args) != 3 {
		return fmt.Errorf("usage: u60-vless6-config SOURCE_JSON DEST_JSON")
	}
	src, dst := os.Args[1], os.Args[2]
	if filepath.Clean(src) == filepath.Clean(dst) {
		return fmt.Errorf("destination must differ from source")
	}
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	b, err = transform(b)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(dst), ".vless6-*.json")
	if err != nil {
		return err
	}
	name := f.Name()
	defer os.Remove(name)
	if _, err = f.Write(b); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	checker := os.Getenv("U60_SING_BOX")
	if checker == "" {
		checker = "/data/proxy-mode/bin/sing-box"
	}
	if out, e := exec.Command(checker, "check", "-c", name).CombinedOutput(); e != nil {
		return fmt.Errorf("sing-box check failed: %s: %w", out, e)
	}
	return os.Rename(name, dst)
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
