package main

import (
 "os"
 "path/filepath"
 "testing"
)

func TestUDPTUNCapable(t *testing.T) {
 tests := []struct {name, config string; valid bool}{
  {"mode-independent", `{"inbounds":[{"type":"tun","tag":"udp-tun-in","interface_name":"u60udp0"}],"outbounds":[{"type":"vless","tag":"custom-vless","packet_encoding":"xudp"}],"route":{"final":"custom-vless"}}`, true},
  {"missing-tun", `{"outbounds":[{"type":"vless","tag":"node","packet_encoding":"xudp"}],"route":{"final":"node"}}`, false},
  {"wrong-interface", `{"inbounds":[{"type":"tun","tag":"udp-tun-in","interface_name":"other0"}],"outbounds":[{"type":"vless","tag":"node","packet_encoding":"xudp"}],"route":{"final":"node"}}`, false},
  {"direct-final", `{"inbounds":[{"type":"tun","tag":"udp-tun-in","interface_name":"u60udp0"}],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct"}}`, false},
  {"missing-xudp", `{"inbounds":[{"type":"tun","tag":"udp-tun-in","interface_name":"u60udp0"}],"outbounds":[{"type":"vless","tag":"node"}],"route":{"final":"node"}}`, false},
  {"bad-override", `{"inbounds":[{"type":"tun","tag":"udp-tun-in","interface_name":"u60udp0"}],"outbounds":[{"type":"vless","tag":"node","packet_encoding":"xudp"}],"route":{"final":"node","rules":[{"inbound":["udp-tun-in"],"outbound":"direct"}]}}`, false},
  {"malformed", `{"inbounds":`, false},
 }
 for _, tc := range tests { t.Run(tc.name, func(t *testing.T) {
  f := filepath.Join(t.TempDir(),"active.json")
  if err := os.WriteFile(f, []byte(tc.config), 0600); err != nil {t.Fatal(err)}
  err := udpTUNCapable(f)
  if (err==nil) != tc.valid {t.Fatalf("valid=%v err=%v",tc.valid,err)}
 }) }
}
