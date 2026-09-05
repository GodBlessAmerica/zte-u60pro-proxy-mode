# ZTE U60 Pro Proxy Mode

`u60proxy` is a portable sing-box proxy manager for the ZTE U60 Pro / MU5250 family.

Current stable release: **2.1.1** (Wi-Fi relay not included yet).

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

Mode 11 is the validated full-proxy path:

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

## Install

The release package contains the prebuilt ARM64 `u60proxy` binary and the validated installer.

```sh
cd /tmp
tar -xzf u60proxy-v2.1.1-final-no-relay.tar.gz
cd u60proxy-v2.1.1-final
./install.sh
```

The installer backs up the existing control plane and data-plane adapter scripts before changing them. Existing private `modeN.json` files are preserved.

For source builds:

```sh
./build-u60proxy.sh
```

This produces `bin/u60proxy` for Linux ARM64.

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
- Wi-Fi relay is intentionally excluded from 2.1.1 and will be developed separately.

## Secrets

Never commit production server addresses, UUIDs, Reality keys, passwords, SSH keys, Wi-Fi credentials, web tokens, or device backups. Repository configs must contain examples only.
