package main

import (
	"bytes"
	"encoding/json"
	"testing"
)

func fixture() []byte {
	return []byte(`{"dns":{"servers":[{"detour":"private-vless","server":"1.1.1.1"}],"strategy":"ipv4_only"},"inbounds":[{"type":"redirect","listen":"0.0.0.0","listen_port":7893},{"type":"tun","interface_name":"u60udp0","address":["172.31.255.1/30"],"mtu":1300,"auto_route":false}],"outbounds":[{"type":"vless","tag":"private-vless","server":"example.invalid","uuid":"private-uuid","tls":{"reality":{"public_key":"private-key"}}}],"route":{"final":"private-vless","rules":[{"ip_is_private":true,"action":"route","outbound":"direct"}]},"custom_preserved":{"value":true}}`)
}
func TestPreservesNodeAndOtherSettings(t *testing.T) {
	src := fixture()
	b, err := transform(src)
	if err != nil {
		t.Fatal(err)
	}
	var old, c map[string]any
	json.Unmarshal(src, &old)
	json.Unmarshal(b, &c)
	for _, key := range []string{"outbounds", "custom_preserved"} {
		x, _ := json.Marshal(old[key])
		y, _ := json.Marshal(c[key])
		if !bytes.Equal(x, y) {
			t.Fatalf("changed %s", key)
		}
	}
	if c["dns"].(map[string]any)["strategy"] != "prefer_ipv6" {
		t.Fatal("DNS remains IPv4-only")
	}
	ib := c["inbounds"].([]any)[1].(map[string]any)
	if ib["mtu"] != float64(1300) || len(ib["address"].([]any)) != 2 {
		t.Fatal("TUN not correctly extended")
	}
	twice, err := transform(b)
	if err != nil || !bytes.Equal(b, twice) {
		t.Fatal("repeated conversion is not idempotent", err)
	}
}
func TestRejectUnsupportedConfigs(t *testing.T) {
	for _, s := range []string{`{}`, `{"outbounds":[{"type":"ssh","tag":"x"}],"route":{"final":"x"}}`, string(bytes.Replace(fixture(), []byte(`"auto_route":false`), []byte(`"auto_route":true`), 1))} {
		if _, err := transform([]byte(s)); err == nil {
			t.Fatal("unsupported config accepted")
		}
	}
}
