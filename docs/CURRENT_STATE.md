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

The project has independent guard state managed by `scripts/guard-control.sh` and exposed through `proxy-mode`:

```sh
proxy-mode guard status
proxy-mode guard udp strict|off
proxy-mode guard ipv6 strict|off
```

Recommended normal state for the stable TCP-only path:

```text
udp_quic_guard=strict
ipv6_guard=strict
```

Turning either guard off can allow direct WAN bypass for traffic the current transparent proxy does not carry.

## COD UDP finding

A real Call of Duty test isolated the remaining compatibility gap:

- With the same VLESS Reality node, RAX3000M TUN/XUDP and Shadowrocket full-tunnel can enter a game room.
- U60 stable mode can log in but cannot enter the room while `udp_quic_guard=strict`.
- Running `proxy-mode guard udp off` immediately makes the game room work.

Conclusion: the game requires UDP after login. The stable U60 path proxies TCP and DNS but does not yet transparently proxy general UDP. With the UDP guard off, that UDP is native WAN traffic and may expose the cellular exit IP. This test is the reason for the experimental Full Proxy UDP work below.

## Experimental Full Proxy UDP

The repository now contains `scripts/udp-tproxy.sh` and `configs/mode10-full-proxy.example.json`.

Experimental design:

```text
TCP -> REDIRECT :7893 -> sing-box -> VLESS
UDP -> mangle/TPROXY :7894 -> policy route table 166 -> sing-box -> VLESS/XUDP
DNS -> existing :5353/:5354 path
IPv6 -> existing leak-guard behavior
```

The UDP helper uses isolated project objects only:

- mangle chain `U60PM_UDP_TPROXY`
- input chain `U60PM_UDP_INPUT`
- fwmark `0x66/0xff`
- policy routing table `166`
- sing-box UDP listener `7894`

Commands:

```sh
/data/proxy-mode/scripts/udp-tproxy.sh preflight
/data/proxy-mode/scripts/udp-tproxy.sh apply
/data/proxy-mode/scripts/udp-tproxy.sh off
/data/proxy-mode/scripts/udp-tproxy.sh status
```

This Full Proxy path is experimental until `sing-box check`, listener creation, policy routing, UDP counters, external IP behavior, and COD room entry are all validated on the U60. Keep the stable production mode untouched while testing Mode 10.

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

## Modes

Production configs live only on the device under `/data/proxy-mode/configs/modeN.json`. Repository configs are examples only.

Current intended numbering:

- Mode 4: VLESS Reality (validated on U60; stable TCP + DNS path)
- Mode 5: direct sing-box SSH outbound (validated on U60)
- Mode 6: SOCKS5 on remote SSH server via sing-box SOCKS outbound with SSH detour (validated on U60)
- Mode 7: SSH A jump host -> SSH B final exit (prepared; validate on target device)
- Mode 8: LAN SOCKS5 upstream (prepared; depends on current LAN proxy address)
- Mode 9: LAN HTTP proxy upstream (prepared; depends on current LAN proxy address)
- Mode 10: VLESS Reality Full Proxy experiment using TCP REDIRECT + UDP TPROXY/XUDP

RAX3000M TUN configs are not copied verbatim to U60. Their outbound logic can usually be reused, while the U60 stable inbound layer remains 7893/5353/5354; Mode 10 adds UDP 7894 without replacing the stable TCP path.

## Web UI

Standalone control service runs on:

```text
http://10.66.0.1:8081/
```

Current source implements:

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
- Full Proxy UDP status/preflight/apply/disable controls
- clearer device tags showing Proxy / DNS / UDP / IPv6 behavior

Config read/write and control endpoints require the local web control token because production JSON may contain sensitive material.

## Startup and persistence

Validated boot recovery for the stable path includes:

- sing-box selected mode
- selective traffic policy
- DNS redirect chains
- IPv4/IPv6 leak-protection chains
- U60 web service on 8081
- log guard

Reference `rc.local` tail should include project start scripts before `exit 0`, including `start-proxy-mode.sh`, `start-u60-web.sh`, and `start-log-guard.sh`.

The experimental UDP TPROXY path is intentionally not auto-enabled at boot until it has been validated.

## Log guard

`scripts/log-guard.sh` is validated. Default design:

- check every 300 seconds
- when a managed log exceeds 5 MiB, keep the latest 1 MiB
- manage `sing-box.log`, `startup.log`, `u60-web.log`, and its own guard log

A reduced-threshold live test successfully trimmed `sing-box.log` and recorded the action.

## Security and repository hygiene

Never commit production mode files or private SSH keys. Do not copy sensitive values from the live device into examples, issues, release notes, or screenshots. Keep stock ports 80/443 untouched. Do not write firmware partitions or flush vendor firewall tables.

## Next steps

1. Install the new `udp-tproxy.sh` on the U60 and run `preflight` only.
2. Install a private Mode 10 based on the known-working VLESS credentials and confirm `sing-box check 10` returns zero.
3. Start Mode 10 and verify UDP listener `:7894` exists before attaching TPROXY rules.
4. Apply UDP TPROXY and inspect mangle counters plus policy rule/table 166.
5. Keep UDP guard strict while testing whether TPROXY consumes game UDP before FORWARD guard.
6. Re-test COD room entry and verify external UDP does not use the native cellular exit.
7. Only after successful validation consider boot persistence for Full Proxy.
8. Validate Modes 7/8/9 and then perform a clean reinstall-from-repository test before a stable release.
