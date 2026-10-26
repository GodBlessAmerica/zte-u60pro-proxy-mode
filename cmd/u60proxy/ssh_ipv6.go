package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
)

// Generate a runtime copy: private mode files and SSH credentials are never rewritten.
func sshIPv6Config(data []byte) ([]byte, bool, error) {
	var cfg map[string]any
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, false, err
	}
	route, _ := cfg["route"].(map[string]any)
	final, _ := route["final"].(string)
	outs, _ := cfg["outbounds"].([]any)
	enabled := false
	for _, v := range outs {
		o, _ := v.(map[string]any)
		if o["tag"] == final && o["type"] == "ssh" {
			enabled = true
		}
	}
	if !enabled {
		return data, false, nil
	}
	ins, _ := cfg["inbounds"].([]any)
	for _, v := range ins {
		o, _ := v.(map[string]any)
		if o["tag"] == "u60-ssh6-in" {
			return nil, false, fmt.Errorf("reserved inbound tag u60-ssh6-in")
		}
	}
	cfg["inbounds"] = append(ins, map[string]any{"type": "redirect", "tag": "u60-ssh6-in", "listen": "::", "listen_port": 7894})
	// Force this dedicated inbound through SSH ahead of user direct/bypass rules.
	// Supplying the IPv6 literal lets sshd dial IPv6 without a local IPv6 WAN.
	rules, _ := route["rules"].([]any)
	route["rules"] = append([]any{map[string]any{"inbound": []string{"u60-ssh6-in"}, "action": "route", "outbound": final}}, rules...)
	b, err := json.MarshalIndent(cfg, "", "  ")
	return append(b, '\n'), true, err
}

func prepareRuntime(src, dst string) error {
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	b, enabled, err := sshIPv6Config(b)
	if err != nil {
		return err
	}
	tmp := dst + ".tmp"
	if err = os.WriteFile(tmp, b, 0600); err != nil {
		return err
	}
	defer os.Remove(tmp)
	if out, e := exec.Command(oldBase+"/bin/sing-box", "check", "-c", tmp).CombinedOutput(); e != nil {
		return fmt.Errorf("runtime config check: %s: %w", out, e)
	}
	if err = os.Rename(tmp, dst); err != nil {
		return err
	}
	flag := "off\n"
	if enabled {
		flag = "on\n"
	}
	return atomicWrite(oldBase+"/runtime/ssh_ipv6", []byte(flag), 0600)
}
