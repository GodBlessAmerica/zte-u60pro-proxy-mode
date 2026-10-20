# Dual-stack preview (opt-in, not production release)

This branch is an **experimental** IPv6 TCP/UDP transparent proxy preview for ZTE U60 Pro Mode 11/12/13. The shipping v2.1.2 remains unchanged.

## Safety and known limits
- **Do not disable IPv6 Guard**. Guard=strict is a requirement for optional IPv6 forwarding.
- Only devices selected for both IPv6 Guard and TCP proxy are routed into the IPv6 TUN. DNS remains governed by the existing per-device DNS switch.
- Carrier IPv6 MUST NOT become a fallback for protected clients.
- The preview has NOT been validated on physical MU5250 hardware. A successful Go CI build is not equivalent to working traffic.
- Server must have outbound IPv6 to reach IPv6-only websites. The IPv4 ingress may still be used.
- Mode 11-13 classification is temporary; convert it to an explicit per-mode config property after testing.
- Prefix `fd75:60:0:167::1/126` is an internal ULA address for the sing-box TUN, not a WAN IPv6 prefix.

## Building
Run the `Build dual-stack preview` GitHub Action. Download the `u60proxy-arm64-dualstack-preview` artifact, unzip and place the executable at `bin/u60proxy` in the checked-out source directory. **Do not install without the CI-built ARM64 binary**.

## Config
Back up your private config before editing it. In each `mode11.json`, `mode12.json`, `mode13.json` you wish to test, modify only the TUN inbound to include both addresses:

```json
"address": ["172.31.255.1/30", "fd75:60:0:167::1/126"]
```

Use the existing `sing-box check -c ...` to validate.

## Install / activate
Copy the source directory and built binary to the router (prefer ADB, and keep a separate management connection), then:

```sh ./install-dualstack-preview.sh```

The installer backs up the control-plane binary and modified scripts and DOES NOT enable IPv6 automatically. Switch to the test mode using 8081. Ensure device IPv6 Guard, TCP and DNS policy are enabled. Opt in:

```
/data/proxy-mode/bin/proxy-mode ipv6proxy enable
/data/proxy-mode/bin/proxy-mode status
```

Disable IPv6 proxy (IPv6 Guard stays enabled):

```
/data/proxy-mode/bin/proxy-mode ipv6proxy disable
```

## Rollback
Before any rollback, `ipv6proxy disable`, then restore the saved originals from `/data/u60proxy-dualstack-backup-*`. Reapply a known-good Mode 11. The installer records its backup path in `/data/u60proxy-dualstack-last-backup`.

## Verification
Compare IPv4/IPv6 reachability with direct cellular disconnected/guard enabled and proxy connected, then disable server IPv6 temporarily and verify that IPv6-only destinations FAIL CLOSED. Inspect `ip6tables -t mangle -S U60PM_V6_TUN`, `ip -6 rule show`, and `ip -6 route show table 167`. Be prepared to roll back if clients cannot browse.
