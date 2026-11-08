# ZTE U60 Pro Proxy Mode

`u60proxy` is a portable sing-box proxy manager for the ZTE U60 Pro / MU5250 family.

Current maintained update release: **v2.1.3-udp-capability** (for existing compatible installations; **not** a clean-install image). Wi-Fi relay is not included.

This repository is intentionally separate from `GodBlessAmerica/openwrt-proxy-mode-suite`; U60 Pro specific work lives here.

## Validated device

- ZTE U60 Pro / MU5250
- Firmware family: B31
- OpenWrt 23.05.4 vendor build
- aarch64 / Snapdragon SDX75
- writable persistent storage: `/data`
- LAN: `10.66.0.1/24` on `br-lan`
- cellular WAN: `rmnet_data0`

## Stable architecture

Modes 11 and 12 have been device-tested for UDP TUN → VLESS XUDP forwarding. This is the full-proxy path:

```text
TCP -> REDIRECT :7893 -> sing-box -> proxy outbound
UDP -> mark 0x67 -> table 167 -> u60udp0 -> sing-box TUN -> proxy outbound
DNS -> REDIRECT :5353/:5354 -> sing-box
IPv6 -> per-device leak guard
```

Table 167 contains a blackhole fallback so selected UDP traffic fails closed instead of escaping through cellular WAN.

## Per-device policy

Policies are keyed by MAC address and survive client IP changes. Each device has four independent switches:

- TCP proxy
- DNS proxy
- UDP proxy
- IPv6 guard

New devices default to direct/off for all four fields.

The web UI determines online state from Wi-Fi association plus `br-lan` neighbor state; DHCP leases are used for identity/IP metadata and are not treated as the sole online signal.

## Web UI

The control plane listens only on:

```text
http://10.66.0.1:8081/
```

The stock ZTE web UI on ports 80/443 is not modified.

## Mode JSON editor

Version 2.1.2 adds an editor directly to the 8081 control panel for existing `/data/proxy-mode/configs/modeN.json` files. Before replacing a config, u60proxy validates JSON syntax, runs `sing-box check`, and creates a timestamped backup. The editor can also save and activate a mode in one step.

Because mode JSON files can contain private server details, the 8081 panel should only be used on a trusted LAN until authentication is added.

## Installation: existing device versus clean device

**Important:** `v2.1.3-udp-capability` is an **incremental update**, not a full factory-fresh install kit. It requires the existing ZTE U60 Pro data-plane core at `/data/proxy-mode`, an installed sing-box binary, the existing `/data/u60proxy` control plane, and the supported firewall and network layout. It cannot install these prerequisites from scratch.

### A. Update an existing compatible U60 Pro (recommended)

Use a **LAN SSH session as root**. Ensure you can reconnect locally if the proxy restarts.

```sh
wget -O /tmp/update-udp-capability.sh \
https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/main/update-udp-capability.sh
sh /tmp/update-udp-capability.sh
```

The script downloads the published ARM64 `v2.1.3-udp-capability` archive, verifies its SHA-256, checks CPU architecture and existing paths, backs up the replaced components and applies the update. **Existing private `modeN.json` configurations, credentials, sing-box and device policies are preserved.** It is designed for compatible ZTE U60 Pro / MU5250 firmware, **not arbitrary OpenWrt devices or phones**.

Release and assets: [v2.1.3-udp-capability](https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/tag/v2.1.3-udp-capability).

After installation, check:

```sh
/data/u60proxy/bin/u60proxy udp-capable
echo "capability_exit_code=$?"
/data/proxy-mode/scripts/udp-tun.sh status
iptables -nvL U60PM_UDP_FAIL
ip -4 rule show
ip -4 route show table 167
```

For a compatible active VLESS profile, `capability_exit_code=0`, `full_proxy_udp=on` and all four UDP TUN readiness fields should be `yes`. A compatible profile needs the `udp-tun-in` inbound bound to `u60udp0`, plus a VLESS `xudp` final outbound. The mode number (11, 12, 13…) does **not** decide whether UDP TUN is enabled. Test actual DNS, TCP/UDP and WAN egress before trusting any profile for privacy-sensitive use.

For rollback, find the extracted package under `/tmp/u60proxy-udp-update-*` (path printed by the updater), then execute its `rollback-udp-capability.sh`. Original component backups are stored under `/data/u60proxy/backups/udp-capability-YYYYMMDD-HHMMSS`.

### B. Brand-new U60 Pro (clean install)

The **target maintained version is still v2.1.3**, but there is **no verified one-command clean installer** in the current Releases:

1. Prepare a supported U60 Pro / MU5250 with root access, compatible vendor firmware, the `/data` persistent filesystem, and LAN SSH access.
2. Install and validate the base `/data/proxy-mode` data plane, sing-box, `proxy-mode` launcher, required startup scripts, and vendor-compatible firewall rules. Do not modify firmware partitions. The old `bootstrap.sh` is for the legacy core, **not** a verified all-in-one v2.1.3 factory installation.
3. Install the 2.1.x `u60proxy` control plane with its `install.sh` **only after** the core is present. Its installer requires a prebuilt ARM64 `bin/u60proxy` and supporting files. The repository does **not** currently publish a ready-to-use v2.1.2 base Release asset; do not assume this step can be completed by downloading the v2.1.3 patch alone.
4. With the base controller and sing-box working, follow **A** to update to `v2.1.3-udp-capability`. Add private VLESS credentials only on-device, not in GitHub.
5. Verify both TCP and UDP, IPv6 blocking, DNS, and public WAN IP before daily use.

**Do not run the v2.1.3 updater on a factory-fresh device expecting it to install everything.** It intentionally refuses if the existing control plane and sing-box are missing. A separate end-to-end factory installer and full-device validation are still needed.

## CLI

```sh
/data/u60proxy/bin/u60proxy status
/data/u60proxy/bin/u60proxy scan
/data/u60proxy/bin/u60proxy apply
/data/u60proxy/bin/u60proxy doctor
/data/u60proxy/bin/u60proxy backup
/data/u60proxy/bin/u60proxy rollback latest
```

Mode management:

```sh
/data/u60proxy/bin/u60proxy mode list
/data/u60proxy/bin/u60proxy mode set 11
```

## Boot behavior

On the tested vendor firmware, a custom procd service was not reliable at cold boot. The stable startup path is:

```text
/etc/rc.local
  -> /data/start-proxy-mode.sh
  -> /data/start-u60proxy-v2.sh
```

`start-u60proxy-v2.sh` waits for `br-lan` / `10.66.0.1` and starts only the web/control plane. It does not restart Mode 11 a second time.

## Safety

- Never flush vendor firewall tables.
- Project rules use isolated `U60PM_*` chains.
- Do not modify firmware partitions or boot slots.
- Keep the stock ZTE web service on 80/443 untouched.
- Production mode configs and credentials must stay private.
- Wi-Fi relay is intentionally excluded from 2.1.2 and will be developed separately.

## Secrets

Never commit production server addresses, UUIDs, Reality keys, passwords, SSH keys, Wi-Fi credentials, web tokens, or device backups. Repository configs must contain examples only.

## Additional UDP capability details

See [UDP-CAPABILITY.md](UDP-CAPABILITY.md) for how mode-independent UDP selection works, requirements, verification, limitations and rollback.
