# Install — u60proxy 2.1.1

This release is intentionally conservative. It keeps the stock ZTE web UI on ports 80/443, stores project state under `/data`, and preserves private `modeN.json` files.

## Recommended install path

Use the packaged 2.1.1 release bundle that contains the prebuilt Linux ARM64 `u60proxy` binary:

```sh
cd /tmp
tar -xzf u60proxy-v2.1.1-final-no-relay.tar.gz
cd u60proxy-v2.1.1-final
./install.sh
```

The installer creates a timestamped backup under `/data/u60proxy-backup-*` before replacing the control plane and per-device adapter scripts.

## Source build

On a development machine with Go installed:

```sh
./build-u60proxy.sh
```

This builds:

```text
bin/u60proxy
```

for Linux ARM64. Put that binary into the release package before running `install.sh` on the U60 Pro.

## Web control

```text
http://10.66.0.1:8081/
```

The controller is LAN-only and does not replace the ZTE web service.

## Device policy

Policies are keyed by MAC address. New clients default to all-off/direct. Available independent controls are:

- TCP proxy
- DNS proxy
- UDP proxy
- IPv6 guard

## CLI

```sh
/data/u60proxy/bin/u60proxy status
/data/u60proxy/bin/u60proxy scan
/data/u60proxy/bin/u60proxy apply
/data/u60proxy/bin/u60proxy devices
/data/u60proxy/bin/u60proxy mode list
/data/u60proxy/bin/u60proxy mode get
/data/u60proxy/bin/u60proxy mode set 11
/data/u60proxy/bin/u60proxy doctor
/data/u60proxy/bin/u60proxy backup
/data/u60proxy/bin/u60proxy rollback latest
```

## Boot startup

The tested vendor firmware did not reliably restore the custom procd service at cold boot. The validated startup path is therefore:

```text
/etc/rc.local
  -> /data/start-proxy-mode.sh
  -> /data/start-u60proxy-v2.sh
```

The u60proxy starter waits for `br-lan` / `10.66.0.1`, scans device state, and supervises the web service. It does not restart the proxy data plane a second time.

## Validation

After install:

```sh
/data/u60proxy/bin/u60proxy doctor
```

The validated Mode 11 installation reports:

```text
summary: fail=0 warn=0
```

and confirms UDP TUN plus the blackhole fail-closed route.

## Rollback

```sh
/data/u60proxy/bin/u60proxy rollback latest
```

A reboot is recommended after rollback.

## Security

Never publish device backup directories or production mode files. They may contain proxy credentials, server addresses, Wi-Fi credentials or other private configuration.

Wi-Fi relay is not included in 2.1.1.
