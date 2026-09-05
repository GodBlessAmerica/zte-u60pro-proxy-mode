# Current validated state

Last updated: 2026-09-05

This file is the handoff point for continuing work on the ZTE U60 Pro / MU5250 proxy project.

## Device baseline

Validated reference device:

- ZTE U60 Pro / MU5250 B31
- OpenWrt 23.05.4 vendor build
- LAN bridge: `br-lan`
- LAN address used by the control service: `10.66.0.1`
- Cellular WAN: `rmnet_data0`
- Persistent writable storage: `/data`
- Root filesystem and `/usr` should be treated as read-only
- Firewall backend: fw3 + iptables/ip6tables legacy

Recovery/administration in the reference setup uses root ADB during development and public-key OpenSSH on port 2222. Do not publish credentials, private keys, web tokens, production proxy JSON files, UUIDs, Reality keys, or server secrets.

## Validated transparent-proxy architecture

The validated Full Proxy design is hybrid rather than all-TUN:

```text
IPv4 TCP client traffic
  -> iptables REDIRECT
  -> 0.0.0.0:7893
  -> sing-box redirect inbound
  -> selected outbound

General IPv4 UDP for selected proxy clients
  -> mangle MARK 0x67/0xff
  -> policy routing table 167
  -> u60udp0 TUN
  -> sing-box tun inbound
  -> VLESS/XUDP

IPv4 DNS
  -> REDIRECT :5353
  -> sing-box DNS/direct inbound
  -> selected proxy path

IPv6 DNS
  -> REDIRECT :5354
  -> sing-box DNS/direct inbound
  -> selected proxy path
```

Validated listeners/interfaces:

- `7893/tcp` transparent TCP
- `5353/tcp+udp` IPv4 DNS
- `5354/tcp+udp` IPv6 DNS
- `u60udp0` TUN, `172.31.255.1/30`, MTU 1300 for Mode 11 UDP
- `8081/tcp` standalone U60 control UI

Project firewall chains use the `U60PM_*` prefix and must never flush or replace ZTE/QCOM vendor tables/chains.

## Per-device policy

Validated selective policy by MAC address:

- Proxy device: IPv4 TCP redirected through sing-box
- Proxy device: IPv4 and IPv6 DNS intercepted
- Proxy device in Mode 11: general IPv4 UDP marked and routed into `u60udp0`
- Proxy device outside Mode 11: non-TCP IPv4 can be blocked by UDP/QUIC guard
- Proxy device: global IPv6 can be blocked by IPv6 leak guard
- Direct device: native IPv4/IPv6 remains available
- LAN/private traffic remains local

MAC selectors are preferred because IPv4 selectors cannot safely identify the same client's IPv6 packets.

## Leak-protection controls

The project has independent guard state managed by `scripts/guard-control.sh` and exposed through `proxy-mode`:

```sh
proxy-mode guard status
proxy-mode guard udp strict|off
proxy-mode guard ipv6 strict|off
```

Recommended normal state:

```text
udp_quic_guard=strict
ipv6_guard=strict
```

Mode 11 keeps the UDP guard strict. `udp-tun.sh` inserts an allow only for marked traffic going from `br-lan` to `u60udp0`, ahead of the general UDP reject chain. Policy table 167 also contains a blackhole default so marked UDP cannot fall back to `rmnet_data0` if the TUN path disappears.

Turning either guard off can allow native WAN bypass for traffic the current transparent proxy does not carry.

## COD UDP finding and validation

A real Call of Duty test isolated the UDP requirement and validated the final design:

- With the stable TCP-only U60 mode and `udp_quic_guard=strict`, the game can log in but cannot enter a room.
- Running `proxy-mode guard udp off` makes room entry work, proving gameplay requires UDP, but that mode allows native WAN UDP and can expose the cellular exit.
- The initial UDP TPROXY experiment matched large packet counters but sing-box never logged `inbound/tproxy`; trying implicit `0.0.0.0`, `127.0.0.1`, and `10.66.0.1` as TPROXY destinations did not make the game work.
- A UDP-only TUN was then created with `auto_route=false`, interface `u60udp0`, address `172.31.255.1/30`, and MTU 1300.
- Selected-client UDP was marked `0x67/0xff`, routed through table 167 to `u60udp0`, and accepted ahead of the strict UDP guard.
- sing-box logs then showed `inbound/tun[udp-tun-in]` followed by `outbound/vless[mode10-vless]: outbound packet connection ...`.
- COD room entry succeeded with this path.

Conclusion: the validated privacy-preserving UDP solution on this U60 is UDP-only TUN + policy routing, not TPROXY.

## Full Proxy Mode 11

Mode 11 is the validated Full Proxy architecture:

```text
TCP -> REDIRECT :7893 -> sing-box -> VLESS
UDP -> MARK 0x67 -> table 167 -> u60udp0 -> sing-box -> VLESS/XUDP
DNS -> existing :5353/:5354 path
IPv6 -> existing strict leak guard
```

`udp-tun.sh` manages only isolated project objects:

- mangle chain `U60PM_UDP_TUN`
- fwmark `0x67/0xff`
- policy routing table `167`
- interface `u60udp0`
- FORWARD accepts for marked `br-lan -> u60udp0` UDP and `u60udp0 -> br-lan` return traffic
- table-167 blackhole fallback

Commands:

```sh
/data/proxy-mode/bin/proxy-mode fullproxy status
/data/proxy-mode/bin/proxy-mode fullproxy on
/data/proxy-mode/bin/proxy-mode fullproxy off
```

Normal operation does not require calling those manually: `proxy-mode start 11` and `proxy-mode restart 11` automatically apply the UDP TUN policy after sing-box creates `u60udp0`. Leaving Mode 11 or stopping proxy-mode removes the UDP TUN policy rules.

The older Mode 10 TPROXY path and `scripts/udp-tproxy.sh` are retained only as experimental/history references and should not be auto-enabled.

## CLI

Validated mode syntax:

```sh
proxy-mode use <number>
proxy-mode start [number]
proxy-mode restart [number]
proxy-mode stop
proxy-mode check [number]
proxy-mode status
proxy-mode traffic on|off|selective|status
proxy-mode device <ip|mac> proxy|direct
proxy-mode guard status
proxy-mode guard udp strict|off
proxy-mode guard ipv6 strict|off
proxy-mode fullproxy status|on|off
```

`start <number>` and `restart <number>` select/validate the requested mode before starting. Device-policy, traffic-policy, and guard changes re-apply Mode 11 UDP TUN policy so selectors and FORWARD ordering stay synchronized.

## Modes

Production configs live only on the device under `/data/proxy-mode/configs/modeN.json`. Repository configs are examples only.

Current intended numbering:

- Mode 4: VLESS Reality; validated stable TCP + DNS path
- Mode 5: direct sing-box SSH outbound; validated
- Mode 6: SOCKS5 on remote SSH server via sing-box SOCKS outbound with SSH detour; validated
- Mode 7: SSH A jump host -> SSH B final exit; prepared, not yet validated
- Mode 8: LAN SOCKS5 upstream; prepared, depends on current LAN proxy address
- Mode 9: LAN HTTP proxy upstream; prepared, depends on current LAN proxy address
- Mode 10: deprecated/experimental VLESS UDP TPROXY attempt
- Mode 11: validated Full Proxy using TCP REDIRECT + UDP-only TUN + VLESS/XUDP

RAX3000M TUN configs are not copied verbatim to U60. Mode 11 keeps TCP on the already-stable REDIRECT path and uses a minimal manually-routed TUN only for UDP.

## Web UI

Standalone control service runs on:

```text
http://10.66.0.1:8081/
```

Current/next UI behavior should represent the validated model, not the abandoned TPROXY experiment:

- engine/current-mode status
- traffic mode: proxy all / direct all / per-device
- connected-client list and per-MAC proxy/direct selection
- human-readable mode cards and labels
- protected read of existing `modeN.json`
- collapsible JSON editor
- `sing-box check` before saving uploaded JSON
- backup existing config to `.bak-web` before replacement
- save and activate selected mode
- independent UDP/QUIC guard control
- independent IPv6 leak guard control
- Mode 11 Full Proxy UDP-TUN status
- clear state indicators for TCP proxy, DNS proxy, UDP tunnel, IPv6 protection, and fail-closed state

Config read/write and control endpoints require the local web control token because production JSON may contain sensitive material.

## Startup and persistence

Validated project startup includes:

- sing-box selected mode
- selective traffic policy
- DNS redirect chains
- IPv4/IPv6 leak-protection chains
- U60 web service on 8081
- log guard

For Mode 11, `proxy-mode start/restart` waits for sing-box startup and then attaches `udp-tun.sh`; `proxy-mode stop` removes the table-167 route/rule and `U60PM_UDP_TUN` rules before stopping sing-box.

Reference `rc.local` tail should include project start scripts before `exit 0`, including `start-proxy-mode.sh`, `start-u60-web.sh`, and `start-log-guard.sh`.

## Log guard

`scripts/log-guard.sh` is validated. Default design:

- check every 300 seconds
- when a managed log exceeds 5 MiB, keep the latest 1 MiB
- manage `sing-box.log`, `startup.log`, `u60-web.log`, and its own guard log

A reduced-threshold live test successfully trimmed `sing-box.log` and recorded the action.

## Security and repository hygiene

Never commit production mode files or private SSH keys. Do not copy sensitive values from the live device into examples, issues, release notes, or screenshots. Keep stock ports 80/443 untouched. Do not write firmware partitions or flush vendor firewall tables.

## Next steps

1. Deploy the repository versions of `udp-tun.sh`, `proxy-mode`, and `stop.sh` to the live U60.
2. Reboot or restart Mode 11 and confirm UDP TUN policy comes up automatically without manual iptables/ip-rule commands.
3. Confirm `proxy-mode fullproxy status` reports TUN ready, policy rule, route, and fail-closed blackhole.
4. Re-test COD room entry after a clean Mode 11 restart and after a device proxy/direct toggle.
5. Update/build/deploy the 8081 UI so it presents Mode 11 UDP-TUN Full Proxy rather than Mode 10 TPROXY.
6. Validate Modes 7/8/9 and then perform a clean reinstall-from-repository test before a stable release.
