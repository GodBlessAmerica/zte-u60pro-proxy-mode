package main

import (
	"encoding/json"
	"testing"
)

func TestSSHIPv6UsesSSHBeforeBypass(t *testing.T) {
	input := []byte(`{"inbounds":[{"type":"redirect","tag":"old","listen":"0.0.0.0","listen_port":7893}],"outbounds":[{"type":"ssh","tag":"ssh","server":"example.invalid","private_key_path":"/private/key"}],"route":{"final":"ssh","rules":[{"ip_version":6,"outbound":"direct"}]}}`)
	b, on, err := sshIPv6Config(input)
	if err != nil || !on {
		t.Fatalf("%v %v", on, err)
	}
	var c map[string]any
	json.Unmarshal(b, &c)
	ins := c["inbounds"].([]any)
	if len(ins) != 2 || ins[1].(map[string]any)["listen"] != "::" {
		t.Fatal("missing dedicated IPv6 listener")
	}
	rules := c["route"].(map[string]any)["rules"].([]any)
	first := rules[0].(map[string]any)
	if first["outbound"] != "ssh" {
		t.Fatal("IPv6 may bypass SSH")
	}
	if c["outbounds"].([]any)[0].(map[string]any)["private_key_path"] != "/private/key" {
		t.Fatal("credentials changed")
	}
}
func TestNonSSHUnchanged(t *testing.T) {
	for _, s := range []string{`{"route":{"final":"direct"},"outbounds":[{"type":"ssh","tag":"unused"}]}`, `{"route":{"final":"vless"},"outbounds":[{"type":"vless","tag":"vless"}]}`} {
		b, on, err := sshIPv6Config([]byte(s))
		if err != nil || on || string(b) != s {
			t.Fatalf("non-SSH modified: %v", err)
		}
	}
}
func TestReservedTagRejected(t *testing.T) {
	_, _, err := sshIPv6Config([]byte(`{"inbounds":[{"tag":"u60-ssh6-in"}],"route":{"final":"s"},"outbounds":[{"type":"ssh","tag":"s"}]}`))
	if err == nil {
		t.Fatal("must reject tag collision")
	}
}
