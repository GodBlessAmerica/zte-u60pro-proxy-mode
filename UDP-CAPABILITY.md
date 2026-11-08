# U60 Pro v2.1.3 — mode-independent UDP capability

## Supported installation type

**v2.1.3-udp-capability is an upgrade for existing compatible ZTE U60 Pro / MU5250 ARM64 devices. It is not a factory-fresh installation package or an installer for arbitrary OpenWrt devices.** The current release contains the rebuilt `u60proxy` ARM64 binary, `proxy-mode` launcher, `traffic.sh`, an upgrade script and a rollback script. It does not provide the full pre-existing data plane, sing-box binary, or per-device production mode configuration.

See [README.md](README.md#installation-existing-device-versus-clean-device) for supported update and clean-device prerequisites.

## Why this upgrade exists

Legacy controller code enabled the UDP TUN only for numeric Mode 11. Switching to Mode 12 disabled the TUN, although Mode 12 already contained a compatible sing-box TUN inbound and VLESS XUDP final outbound.

The updated controller checks the active `/data/proxy-mode/runtime/active.json` configuration instead of the mode number:
- `inbounds`: `type: tun`, `tag: udp-tun-in`, `interface_name: u60udp0`
- `route.final`: names a `vless` outbound with `packet_encoding: xudp`
- No conflicting explicit route override for `udp-tun-in`

Matching configurations can enable UDP TUN regardless of their numeric mode ID. Non-matching configurations are not automatically converted.

## Existing-device upgrade

Run from a LAN SSH session as root; do not depend on the proxy for access during the change:

```sh
wget -O /tmp/update-udp-capability.sh https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/main/update-udp-capability.sh
sh /tmp/update-udp-capability.sh
```

The updater downloads [v2.1.3-udp-capability](https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/tag/v2.1.3-udp-capability), verifies its SHA-256, checks for a compatible ARM64 installation, and backs up the replaced files. Private `modeN.json`, credentials, saved policies, firmware, and the sing-box binary are not replaced.

## Verification

```sh
/data/u60proxy/bin/u60proxy udp-capable
echo "capability_exit_code=$?"
/data/proxy-mode/scripts/udp-tun.sh status
ip -4 rule show
ip -4 route show table 167
iptables -nvL U60PM_UDP_FAIL
ip6tables -nvL U60PM_GUARD6
```

A compatible active VLESS profile should return exit code 0 and report `full_proxy_udp=on`, `udp_tun_chain=yes`, `udp_policy_rule=yes`, `udp_tun_route=yes`, and `udp_fail_closed=yes`. Check the sing-box logs for `inbound/tun[udp-tun-in]` and the correct VLESS outbound tag with packet connections. Perform separate real-world IP/DNS, WebRTC, IPv6 and WAN-egress checks.

The independent `U60PM_UDP_FAIL` IPv4 FORWARD filter rejects public UDP forwarded directly to non-TUN interfaces for devices with TCP proxy enabled; local-network destinations are excluded. Existing IPv6 protection remains a separate per-device guard.

## Rollback

The updater prints its extracted directory under `/tmp/u60proxy-udp-update-*`. Execute that directory's `rollback-udp-capability.sh` as root to restore the most recent stored backup, recorded in `/data/u60proxy/runtime/udp-capability-backup`. Reconnect by LAN SSH if the controller restarts.

## Clean-device limitation

A new device must first have a compatible vendor firmware, root access, persistent `/data` filesystem, core `/data/proxy-mode` scripts and sing-box, and a working base `/data/u60proxy` installation. The GitHub repository currently does not publish a verified end-to-end, one-command v2.1.3 clean-install image. The updater intentionally refuses a device where these prerequisites are missing. Do not treat the legacy `bootstrap.sh` as a validated all-in-one installer.

## Privacy limitations

Successful TUN interception and the installed leak guards are not proof of complete leak freedom. Advanced routing rules, DNS over HTTPS, device-specific forwarding, and temporary firewall reset events need separate tests. Never upload real VLESS secrets, UUIDs, private keys, server credentials or backups to the public repository.
