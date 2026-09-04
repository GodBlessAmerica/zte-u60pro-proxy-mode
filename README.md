# ZTE U60 Pro Proxy Mode

Portable sing-box proxy manager for the ZTE U60 Pro / MU5250 family.

This project is intentionally separate from `GodBlessAmerica/openwrt-proxy-mode-suite`. U60 Pro specific changes live here only.

## Reference device

Validated on:

- ZTE U60 Pro / MU5250
- Firmware family: B31
- OpenWrt 23.05.4 (ZTE/Qualcomm vendor build)
- Architecture: aarch64 / aarch64_cortex-a53
- Persistent writable storage: `/data`
- LAN bridge: `br-lan`
- Cellular WAN: `rmnet_data0`
- Firewall: fw3 + iptables/ip6tables legacy

## What works

The current validated architecture uses isolated firewall chains plus sing-box:

- IPv4 TCP transparent proxy through REDIRECT -> sing-box
- Per-device policy by IPv4 address or, preferably, MAC address
- `all`, `off`, and `selective` traffic modes
- Per-device proxy/direct switching
- IPv4 DNS interception for proxy devices
- IPv6 DNS interception for proxy devices
- IPv4 UDP/QUIC leak protection for proxy devices
- IPv6 WAN leak protection for proxy devices
- Direct devices keep native IPv4/IPv6 connectivity
- Policy and mode state survive reboot when the supplied startup flow is installed
- Standalone LAN-only control UI can be bound to `10.66.0.1:8081`

## Current traffic model

For a device marked `proxy` by MAC:

```text
IPv4 TCP          -> REDIRECT :7893 -> sing-box -> proxy outbound
IPv4 DNS :53      -> REDIRECT :5353 -> sing-box -> proxy outbound
IPv6 DNS :53      -> REDIRECT :5354 -> sing-box -> proxy outbound
Other IPv4 UDP    -> blocked from WAN to prevent bypass
Global IPv6       -> blocked from WAN to prevent bypass
LAN/private IPv4  -> left local
IPv6 link-local   -> left local
```

For a device marked `direct`, traffic is not intercepted by the project chains.

The IPv6 behavior for proxy devices is currently **leak protection**, not full IPv6 transparent proxying. DNS can be intercepted over IPv6, while other global IPv6 traffic is rejected so the cellular IPv6 address cannot bypass the proxy.

## CLI

```sh
/data/proxy-mode/bin/proxy-mode status
/data/proxy-mode/bin/proxy-mode list
/data/proxy-mode/bin/proxy-mode use 4
/data/proxy-mode/bin/proxy-mode start 4
/data/proxy-mode/bin/proxy-mode restart 4
/data/proxy-mode/bin/proxy-mode stop

/data/proxy-mode/bin/proxy-mode traffic on
/data/proxy-mode/bin/proxy-mode traffic off
/data/proxy-mode/bin/proxy-mode traffic selective

/data/proxy-mode/bin/proxy-mode device aa:bb:cc:dd:ee:ff proxy
/data/proxy-mode/bin/proxy-mode device aa:bb:cc:dd:ee:ff direct
```

MAC selectors are strongly recommended when IPv6 leak protection is required because an IPv4 address alone cannot reliably identify the same client's IPv6 packets.

## Ports used by the validated setup

- `7893/tcp`: transparent IPv4 TCP redirect inbound
- `5353/tcp+udp`: IPv4 DNS proxy inbound
- `5354/tcp+udp`: IPv6 DNS proxy inbound
- `8081/tcp`: optional standalone LAN-only web control service
- `2222/tcp`: optional OpenSSH administration in the reference setup

## Safety model

- Never flush vendor firewall tables.
- Never replace ZTE/QCOM chains.
- Project rules live in dedicated `U60PM_*` chains and are reversible.
- Keep the stock ZTE web service on ports 80/443 untouched.
- Keep recovery access available while developing or changing boot startup.
- Do not publish production `modeN.json` files.

## Secrets

Production sing-box configs may contain server addresses, UUIDs, Reality keys, passwords or subscription URLs. Keep them only on the device or in a private secret store. The repository must contain examples only, never production credentials.
