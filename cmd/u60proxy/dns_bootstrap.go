package main

import (
 "bytes"
 "encoding/json"
 "regexp"
)

var bootstrapHost = regexp.MustCompile(`^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$`)
var bootstrapNumeric = regexp.MustCompile(`^[0-9.]+$`)

// Only simple single-hop IPv4 hostname profiles with one proxied DoH.
// Preserve custom resolvers, literal addresses, and chained profiles.
func normalizeBootstrap(content string) (string, error) {
 var c map[string]any
 d := json.NewDecoder(bytes.NewBufferString(content))
 d.UseNumber()
 if err := d.Decode(&c); err != nil { return "", err }
 obs, _ := c["outbounds"].([]any)
 if len(obs)==0 { return content,nil }
 o, _ := obs[0].(map[string]any)
 server, _ := o["server"].(string)
 if o["type"]!="vless" || !bootstrapHost.MatchString(server) || bootstrapNumeric.MatchString(server) || o["domain_resolver"]!=nil { return content,nil }
 if v,ok:=o["detour"]; ok && v!=nil && v!="" { return content,nil }
 count:=0
 for _, item := range obs { if x,ok:=item.(map[string]any); ok && x["type"]=="vless" { count++ } }
 if count!=1 { return content,nil }
 route,_:=c["route"].(map[string]any)
 dns,_:=c["dns"].(map[string]any)
 tag,ok:=o["tag"].(string)
 if !ok || tag=="" || route["final"]!=tag || route["default_domain_resolver"]!=nil { return content,nil }
 servers,_:=dns["servers"].([]any)
 if len(servers)!=1 { return content,nil }
 remote,_:=servers[0].(map[string]any)
 remoteTag,ok:=remote["tag"].(string)
 if !ok || remoteTag=="" || remoteTag=="dns-bootstrap" || remote["type"]!="https" || remote["detour"]!=tag { return content,nil }
 if v:=dns["final"]; v!=nil && v!=remoteTag { return content,nil }
 if v:=dns["strategy"]; v!=nil && v!="ipv4_only" { return content,nil }
 if v:=dns["rules"]; v!=nil { a,ok:=v.([]any); if !ok || len(a)!=0 { return content,nil } }
 dns["final"]=remoteTag
 dns["strategy"]="ipv4_only"
 dns["servers"]=append(servers,map[string]any{"type":"https","tag":"dns-bootstrap","server":"223.5.5.5","server_port":443,"path":"/dns-query","tls":map[string]any{"enabled":true,"server_name":"dns.alidns.com"}})
 resolver:=map[string]any{"server":"dns-bootstrap","strategy":"ipv4_only"}
 o["domain_resolver"]=resolver
 route["default_domain_resolver"]=resolver
 b,err:=json.MarshalIndent(c,"","  ")
 return string(b),err
}
