# Architecture

## Control plane

`u60proxy` is a static Go ARM64 binary. It owns:

- device policy database under `/data/u60proxy/state`
- client discovery and online-state calculation
- mode selection UI/API
- embedded web UI on `10.66.0.1:8081`
- policy-file generation

## Data plane

The existing `/data/proxy-mode` sing-box core remains the data plane.

Policy files:

```text
/data/proxy-mode/runtime/proxy_devices
/data/proxy-mode/runtime/dns_devices
/data/proxy-mode/runtime/udp_devices
/data/proxy-mode/runtime/ipv6_devices
```

`traffic.sh` consumes TCP/DNS/IPv6 selectors independently. `udp-tun.sh` consumes `udp_devices` independently.

## Mode 11

```text
selected TCP  -> U60PM_REDIRECT -> :7893
selected DNS  -> U60PM_DNS4/6   -> :5353/:5354
selected UDP  -> U60PM_UDP_TUN  -> fwmark 0x67 -> table 167 -> u60udp0
selected IPv6 -> U60PM_GUARD6 leak protection
```

Private/local destinations are excluded from interception where appropriate.

## Startup

The vendor firmware reliably executes `/etc/rc.local`. The validated order is:

```text
start-openssh.sh
start-proxy-mode.sh
start-u60proxy-v2.sh
start-log-guard.sh
```

The control-plane starter waits for `br-lan` and avoids duplicate `u60proxy serve` processes.
