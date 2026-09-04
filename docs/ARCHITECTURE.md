# Architecture

## Runtime boundary

The project treats the ZTE vendor firmware as immutable infrastructure.

Persistent project state lives under:

```text
/data/proxy-mode
```

The stock ZTE web service on ports 80/443 is not modified.

## Networking

Reference interfaces:

- LAN bridge: `br-lan`
- Cellular WAN: `rmnet_data0`
- Firewall backend: `iptables-legacy` / `ip6tables-legacy` with fw3

The project never flushes vendor tables or replaces ZTE/QCOM chains. Transparent proxying is implemented with dedicated reversible `U60PM_*` chains inserted ahead of vendor forwarding/NAT processing.

## Validated transparent proxy path

TCP TPROXY/TUN experiments were not reliable enough on the reference vendor kernel, so the validated production path is REDIRECT-based IPv4 TCP proxying.

```text
LAN client
  -> br-lan
     -> U60PM_DNS4 / U60PM_DNS6 (DNS interception for proxy devices)
     -> U60PM_REDIRECT (IPv4 TCP)
     -> sing-box
     -> configured proxy outbound
```

Validated local sing-box inbounds:

- `7893/tcp`: IPv4 transparent TCP REDIRECT inbound
- `5353/tcp+udp`: IPv4 DNS interception inbound
- `5354/tcp+udp`: IPv6 DNS interception inbound

## Per-device policy

Policy state is stored as selectors under `/data/proxy-mode/runtime`.

Supported modes:

- `off`: no project interception
- `all`: proxy all LAN clients except explicit direct selectors
- `selective`: proxy only explicit proxy selectors

Selectors may be IPv4 addresses or MAC addresses. MAC selectors are preferred because they continue to identify IPv6 packets from the same client.

For a device marked `proxy` by MAC:

```text
IPv4 TCP        -> sing-box via REDIRECT
IPv4 DNS        -> sing-box via :5353
IPv6 DNS        -> sing-box via :5354
Other IPv4 UDP  -> rejected from WAN
Global IPv6     -> rejected from WAN
LAN/private      -> preserved
IPv6 link-local  -> preserved
```

For a device marked `direct`, project chains return without proxying or leak blocking.

## IPv6 model

The current design provides per-device IPv6 leak protection, not full IPv6 transparent proxying.

IPv6 DNS requests from proxy devices can be redirected into sing-box, while other global IPv6 forwarding from those devices is rejected. This prevents the cellular IPv6 address from bypassing an IPv4 proxy path.

## Process model

```text
proxy-mode
  -> select/validate modeN.json
  -> runtime/active.json
  -> start.sh
     -> sing-box
     -> traffic.sh apply

u60-web :8081
  -> /data/proxy-mode/bin/proxy-mode
```

The standalone control service should bind only to the LAN address, for example `10.66.0.1:8081`.

Write actions require a locally generated token stored at:

```text
/data/proxy-mode/runtime/web.token
```

## Mode model

User configs are stored as:

```text
/data/proxy-mode/configs/modeN.json
```

Selecting a mode validates it with `sing-box check` before atomically replacing:

```text
/data/proxy-mode/runtime/active.json
```

`proxy-mode start N` and `proxy-mode restart N` select and validate mode `N` before starting.

No production mode files belong in the repository.
