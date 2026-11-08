# UDP capability preview (mode independent)

This update targets the ZTE U60 Pro with the 2.1.2 control plane.

## Why
The original control plane enabled UDP TUN only when the numeric mode was 11. Mode 12 and any new mode disabled it even if its sing-box JSON had a compatible TUN.

## Changes
- Go CLI checks the **active JSON** for an `udp-tun-in` TUN inbound bound to `u60udp0`, and a `route.final` referencing a VLESS outbound with `packet_encoding: xudp`.
- Shell mode start/restart uses that capability check instead of mode number.
- An independent `U60PM_UDP_FAIL` FORWARD chain rejects **public IPv4 UDP not going to u60udp0** for clients with TCP proxy enabled. This is independent of the legacy `udp_quic_guard` switch.
- Existing private `modeN.json`, VLESS credentials, device policy, sing-box binary and firmware are not modified.

## Limitations
Not all UDP configurations are supported. Any explicit route policy, rule-set or other advanced routing that bypasses the default route requires separate validation. IPv6 protection continues to rely on existing per-device IPv6 guard rules. A real device-side egress leak test is required before calling this leak-free.

## Installation
Download the `u60proxy-udp-capability-preview.tar.gz` release asset from GitHub, transfer to the device, then from a root SSH shell:

```sh
cd /tmp
tar -xzf u60proxy-udp-capability-preview.tar.gz
cd u60proxy-udp-capability-preview
sh ./install-udp-capability.sh
/data/proxy-mode/bin/proxy-mode status
```

Install from local LAN, not over a connection that depends on the proxy. The script backs up replaced files under `/data/u60proxy/backups/` and prints the path. Roll back with `sh ./rollback-udp-capability.sh`.

## Verify
Set a tested VLESS mode that has compatible JSON and enable the required device switches. Check:

```sh
/data/u60proxy/bin/u60proxy udp-capable
/data/proxy-mode/scripts/udp-tun.sh status
ip -4 rule show
iptables -nvL U60PM_UDP_FAIL
```

Check that `udp_tun_chain`, `udp_policy_rule`, `udp_tun_route`, and `udp_fail_closed` are all `yes`. Test both TCP and UDP traffic as well as WAN egress on the device. A working TUN path does not by itself prove there is no leak.
