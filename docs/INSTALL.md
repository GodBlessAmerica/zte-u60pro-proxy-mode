# Install

The installer is intentionally conservative: it copies project files under `/data` and does not modify firmware partitions or the stock ZTE web service.

## Prerequisites

- root shell through SSH or ADB
- writable `/data`
- aarch64 sing-box binary at `/data/proxy-mode/bin/sing-box`
- `iptables` and `ip6tables` legacy support
- MAC match support if per-device IPv6 leak protection is required

## Install from source

```sh
cd /tmp
rm -rf zte-u60pro-proxy-mode-main u60proxy.tar.gz
wget -O u60proxy.tar.gz https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/archive/refs/heads/main.tar.gz
tar -xzf u60proxy.tar.gz
cd zte-u60pro-proxy-mode-main
sh install.sh
```

The installer creates a local web-control token at:

```text
/data/proxy-mode/runtime/web.token
```

Keep it private.

## CLI

```sh
/data/proxy-mode/bin/proxy-mode preflight
/data/proxy-mode/bin/proxy-mode status
/data/proxy-mode/bin/proxy-mode list
/data/proxy-mode/bin/proxy-mode use 4
/data/proxy-mode/bin/proxy-mode start 4
/data/proxy-mode/bin/proxy-mode restart 4
/data/proxy-mode/bin/proxy-mode stop
```

Traffic policy:

```sh
/data/proxy-mode/bin/proxy-mode traffic on
/data/proxy-mode/bin/proxy-mode traffic off
/data/proxy-mode/bin/proxy-mode traffic selective
```

Per-device policy:

```sh
/data/proxy-mode/bin/proxy-mode device aa:bb:cc:dd:ee:ff proxy
/data/proxy-mode/bin/proxy-mode device aa:bb:cc:dd:ee:ff direct
```

MAC selectors are recommended. They continue to identify a client when DHCP changes its IPv4 address and allow the IPv6 guard to match the same device.

## Expected sing-box inbounds for the validated mode

The production mode used by the reference setup exposes:

- `7893/tcp`: transparent IPv4 TCP redirect
- `5353/tcp+udp`: IPv4 DNS interception
- `5354/tcp+udp`: IPv6 DNS interception

A mode config should route those flows through the desired proxy outbound. Production credentials must not be committed to this repository.

## Web control

The validated standalone controller binds to the LAN only, for example:

```text
http://10.66.0.1:8081/
```

It is separate from the stock ZTE web UI on ports 80/443.

## Boot startup

Only add boot startup after manual validation. A reference order is:

```text
zte-agent
OpenSSH
proxy-mode startup
u60-web
```

The proxy startup flow should wait briefly for the cellular WAN interface, restore the selected mode, start sing-box, and reapply the saved traffic policy.

After enabling boot startup, verify after a full reboot:

```sh
/data/proxy-mode/bin/proxy-mode status
netstat -lnptu 2>/dev/null | grep -E ':7893|:5353|:5354|:8081'
ip6tables -t nat -L U60PM_DNS6 -n -v
ip6tables -L U60PM_GUARD6 -n -v
```

## Rollback

Disable project interception without touching the vendor firewall:

```sh
/data/proxy-mode/bin/proxy-mode traffic off
```

Stop sing-box:

```sh
/data/proxy-mode/bin/proxy-mode stop
```

Project rules use dedicated `U60PM_*` chains and should remain reversible. Never flush the vendor firewall tables.
