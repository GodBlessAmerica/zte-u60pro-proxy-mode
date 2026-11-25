package main
import (
 "encoding/json"
 "strings"
 "testing"
)
func TestNormalizeBootstrap(t *testing.T) {
 src:=`{"dns":{"servers":[{"type":"https","tag":"remote","server":"1.1.1.1","detour":"v"}]},"outbounds":[{"type":"vless","tag":"v","server":"node.example.com"},{"type":"direct","tag":"direct"}],"route":{"final":"v"}}`
 got,e:=normalizeBootstrap(src)
 if e!=nil || !json.Valid([]byte(got)) || !strings.Contains(got,"default_domain_resolver") || !strings.Contains(got,"dns.alidns.com") { t.Fatal("normalization failed",e) }
 again,e:=normalizeBootstrap(got)
 if e!=nil || again!=got { t.Fatal("not idempotent") }
 for _,server:=range []string{"192.0.2.1","2001:db8::1"} {
  s:=strings.ReplaceAll(src,"node.example.com",server)
  got,e:=normalizeBootstrap(s)
  if e!=nil || got!=s { t.Fatal("literal changed",e) }
 }
 custom:=strings.Replace(src,`"final":"v"`,`"final":"v","default_domain_resolver":"custom"`,1)
 got,e=normalizeBootstrap(custom)
 if e!=nil || got!=custom { t.Fatal("custom resolver changed") }
}
