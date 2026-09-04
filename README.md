# ZTE U60 Pro Proxy Mode

Portable sing-box proxy manager for the ZTE U60 Pro / MU5250 family.

This project is intentionally separate from `GodBlessAmerica/openwrt-proxy-mode-suite`. It may reuse ideas and patterns from that project, but U60 Pro specific changes live here only.

## Target device

Reference device:

- ZTE U60 Pro / MU5250
- Firmware family: B31
- OpenWrt 23.05.4 (ZTE/Qualcomm vendor build)
- Architecture: aarch64 / aarch64_cortex-a53
- Writable persistent storage: `/data`
- Read-only system paths such as `/usr`
- LAN: `br-lan`
- Cellular WAN: `rmnet_data0`
- Firewall: fw3 + iptables-legacy
- TUN: available via `/dev/net/tun`

## Design goals

- Keep vendor firmware, modem, Wi-Fi, battery and Qualcomm networking intact.
- Store project binaries/config/state under `/data/proxy-mode`.
- Never flush or replace the vendor firewall ruleset.
- Add only isolated, reversible rules when transparent proxying is enabled.
- Use public-key SSH for administration.
- Keep ADB available during development as a recovery path.
- Provide a web UI through an isolated dashboard rather than modifying ZTE's stock web root.

## Planned layout

```text
/data/proxy-mode/
├── bin/
├── configs/
├── logs/
├── runtime/
└── web/
```

## Current status

Project bootstrap. The first milestone is a safe CLI with preflight checks, sing-box process control, mode switching, and a read-only status web page.

## Safety

Do not publish production `modeN.json` files. They may contain server addresses, UUIDs, passwords, private keys or subscription URLs.
