# ZTE U60 Pro Full Install — v2.1.3

**Status:** First complete package for a rooted compatible ZTE U60 Pro / MU5250 (aarch64) with the tested vendor OpenWrt layout. This is not a firmware flasher and not a universal OpenWrt package. Fresh-device field testing is still required.

## Included components

- Prebuilt ARM64 Go `u60proxy` controller and local 8081 web UI
- Pinned, SHA-256-verified sing-box 1.14.0 binary, bundled during the GitHub build
- `proxy-mode` launcher, TUN routing, DNS interception, per-client firewall scripts and UDP fail-closed rules
- Boot scripts, backup/doctor/rollback helpers, and **non-secret** sample Mode 11 VLESS Reality + XUDP template

**Does not include:** real VLESS credentials, a configured proxy node, firmware, root access, Wi-Fi hotspot provisioning, or a promise of full no-leak behavior.

## Hardware and firmware prerequisites

- Root access via a **direct LAN SSH connection**, not a connection traversing the proxy.
- `aarch64` ZTE U60 Pro / MU5250, writable persistent `/data`.
- Vendor LAN `br-lan` with `10.66.0.1`, cellular WAN `rmnet_data0`, `/dev/net/tun`.
- `iproute2`, `iptables-legacy`, `ip6tables`, BusyBox essentials, working outbound HTTPS and sufficient disk space.
- **Fresh /data installation only:** /data/proxy-mode and /data/u60proxy must not exist. Use the incremental [v2.1.3 updater](UDP-CAPABILITY.md) instead for existing systems.

## Quick install

```sh
wget -4 -T 30 -O /tmp/u60pro-full-install.sh https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/feature/full-install-u60pro-v2.1.3/full-install/bootstrap-full.sh
sh /tmp/u60pro-full-install.sh
```

The bootstrap checks the downloaded full-package SHA-256 against the separate release checksum, unpacks and runs the installer. The full package is published at the [v2.1.3-u60pro-full](https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/tag/v2.1.3-u60pro-full) tag. Review the shell script before running it as root. You can instead download the tarball and checksum to a PC, transfer both to the U60 Pro and verify them there.

On successful installation, the local management UI is http://10.66.0.1:8081/ — **use only on a trusted LAN**. The original vendor UI on ports 80/443 is not touched.

## First-time VLESS setup

The installer intentionally does **not** activate sample credentials. Private mode files are created only by the device operator.

```sh
cp /data/proxy-mode/configs/mode11.example.json /data/proxy-mode/configs/mode11.json
# Edit /data/proxy-mode/configs/mode11.json, replacing all placeholder values.
# Do NOT post the real JSON to public GitHub.
/data/proxy-mode/bin/sing-box check -c /data/proxy-mode/configs/mode11.json
/data/u60proxy/bin/u60proxy mode set 11
/data/proxy-mode/bin/proxy-mode status
```

The controller detects whether the active profile has the `udp-tun-in` inbound on `u60udp0` and a `route.final` targeting VLESS with `packet_encoding: xudp`. Future mode IDs need not be 11.

Enable TCP, DNS, UDP and IPv6 guard for chosen clients in the web UI, then verify:

```sh
/data/u60proxy/bin/u60proxy udp-capable
/data/proxy-mode/scripts/udp-tun.sh status
iptables -nvL U60PM_UDP_FAIL
ip6tables -nvL U60PM_GUARD6
```

Test live public IPv4, IPv6, WebRTC, DNS and WAN packet egress. TUN status or successful VLESS log entries **do not alone establish zero leakage**.

## Limitations and recovery

- The installer refuses existing installations rather than overwriting unknown private configurations.
- Fresh installation does not change the device firmware or boot partitions, but adds a startup hook to `/etc/rc.local` and backs up the original as `/data/u60proxy/runtime/rc.local.before-full`.
- Boot starts the web control plane. The proxy process starts only if `active.json` exists and passes `sing-box check`.
- For clean rollback on a device without user data, carefully restore the saved rc.local and remove only the paths installed by this package. Avoid blindly removing /data paths on devices with other services.
- If remote GitHub access is blocked on your network, copy the release archive/checksum from a PC instead.
