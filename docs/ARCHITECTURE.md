# Architecture

## Runtime boundary

The project treats the ZTE vendor firmware as immutable infrastructure.

Persistent project state lives under:

```text
/data/proxy-mode
```

Dashboard assets and CGI entry points live under the isolated OpenUI web root:

```text
/data/www/proxy-mode
/data/www/cgi-bin/proxy-api
```

## Networking

Reference interfaces:

- LAN bridge: `br-lan`
- Cellular WAN: `rmnet_data0`
- TUN support: `/dev/net/tun`
- Firewall backend: `iptables-legacy` / fw3

The project must never flush vendor tables or replace ZTE/QCOM chains. Future transparent-proxy support will use dedicated project chains and reversible jumps only.

## Process model

```text
browser :8080
  -> isolated uhttpd
     -> static dashboard
     -> /cgi-bin/proxy-api
        -> /data/proxy-mode/bin/proxy-mode
           -> /data/proxy-mode/bin/sing-box
```

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

No production mode files belong in the repository.
