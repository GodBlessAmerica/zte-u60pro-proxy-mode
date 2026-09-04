# Current validated state

Last updated: 2026-09-04

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

The stable U60 design does not use TUN for client forwarding. It uses isolated, reversible firewall chains plus sing-box:

```text
IPv4 TCP client traffic
  -> iptables REDIRECT
  -> 0.0.0.0:7893
  -> sing-box redirect inbound
  -> selected outbound

IPv4 DNS
  -> REDIRECT :5353
  -> sing-box DNS/direct inbound
  -> selected proxy path

IPv6 DNS
  -> REDIRECT :5354
  -> sing-box DNS/direct inbound
  -> selected proxy path
```

Validated listeners:

- `7893/tcp` transparent TCP
- `5353/tcp+udp` IPv4 DNS
- `5354/tcp+udp` IPv6 DNS
- `8081/tcp` standalone U60 control UI

Project firewall chains use the `U60PM_*` prefix and must never flush or replace ZTE/QCOM vendor tables/chains.

## Per-device policy

Validated selective policy by MAC address:

- Proxy device: IPv4 TCP redirected through sing-box
- Proxy device: IPv4 and IPv6 DNS intercepted
- Proxy device: non-TCP IPv4 can be blocked by UDP/QUIC guard
- Proxy device: global IPv6 can be blocked by IPv6 leak guard
- Direct device: native IPv4/IPv6 remains available
- LAN/private traffic remains local

MAC selectors are preferred because IPv4 selectors cannot safely identify the same client's IPv6 packets.

## Leak-protection controls

The project now has independent guard state managed by `scripts/guard-control.sh` and exposed through `proxy-mode`:

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

Turning either guard off can allow direct WAN bypass for traffic the current transparent proxy does not carry.

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
```

Important historical fix: `start 4` originally ignored the mode argument. The CLI was changed so `start <number>` and `restart <number>` select/validate the requested mode before starting.

## Validated modes

Production configs live only on the device under `/data/proxy-mode/configs/modeN.json`. Repository configs are examples only.

Current intended numbering:

- Mode 4: VLESS Reality (validated on U60)
- Mode 5: direct sing-box SSH outbound (validated on U60)
- Mode 6: SOCKS5 on remote SSH server via sing-box SOCKS outbound with SSH detour (validated on U60)
- Mode 7: SSH A jump host -> SSH B final exit (prepared; validate on target device)
- Mode 8: LAN SOCKS5 upstream (prepared; depends on current LAN proxy address)
- Mode 9: LAN HTTP proxy upstream (prepared; depends on current LAN proxy address)

RAX3000M TUN configs are not copied verbatim to U60. Their outbound logic can usually be reused, while the U60 inbound layer should remain the validated 7893/5353/5354 REDIRECT design.

## Web UI

Standalone control service runs on:

```text
http://10.66.0.1:8081/
```

Implemented/planned control-surface features:

- engine/current-mode status
- traffic mode: proxy all / direct all / per-device
- connected-client list and per-MAC proxy/direct selection
- mode list
- protected read of existing `modeN.json`
- JSON editor
- `sing-box check` before saving uploaded JSON
- backup existing config to `.bak-web` before replacement
- save and activate selected mode
- independent UDP/QUIC guard control
- independent IPv6 leak guard control

Config read/write endpoints require the local web control token because production JSON may contain sensitive material.

The latest UI work is focused on improving labels/layout and eliminating `undefined` fields when rendering modes/clients. If the device binary is newer than repository source, reconcile `cmd/u60-web/main.go` before making the next release.

## Startup and persistence

Validated boot recovery includes:

- sing-box selected mode
- selective traffic policy
- DNS redirect chains
- IPv4/IPv6 leak-protection chains
- U60 web service on 8081
- log guard

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

1. Reconcile and commit the latest UI source used to build the current device binary if needed.
2. Validate Mode 7 on the real jump-host pair.
3. Validate Mode 8/9 after confirming the current LAN SOCKS/HTTP upstream address and port.
4. Finish UI polish and mode labels.
5. Update installer/startup integration for every newly added script.
6. After a clean reinstall-from-repository test, bump VERSION and create the first stable release.
