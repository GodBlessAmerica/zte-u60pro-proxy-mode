# ZTE U60 Pro Proxy Mode — v2.1.4

Portable sing-box proxy manager for rooted ZTE U60 Pro / MU5250 (ARM64). Version 2.1.4 is a **release candidate**: IPv6 single-node upstream and the expanded UI have been exercised by the device operator; unified upgrade, clean installation and full reboot/reconnect regression still require device verification.

## 中文安装说明

### 已有设备升级（保留配置）

适用于已有兼容的 /data/proxy-mode 和 /data/u60proxy 安装。通过可信 LAN SSH，以 root 身份执行。先查看脚本内容，再执行：

```sh
curl -fL -o /tmp/u60-update.sh https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/main/update.sh
sh /tmp/u60-update.sh
```

统一升级包包含 ARM64 控制程序、代理核心脚本、IPv6 检测及回滚。保留 sing-box、私人 JSON、设备策略、模式名称和当前运行代理；新的转发脚本在下次切换模式或应用策略时生效。

回滚：`/data/u60proxy/bin/rollback-v2.1.4`。

### 新设备完整安装

仅限已 root、兼容固件、可写 /data、没有旧项目安装的 U60 Pro / MU5250。不是刷机或获取 root 的工具。

```sh
curl -fL -o /tmp/u60-full.sh https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/main/full-install/bootstrap-full.sh
sh /tmp/u60-full.sh
```

安装后进入 http://10.66.0.1:8081，使用新建 JSON 功能录入私人节点。完整包提供 IPv4 和 IPv6 模板，不自动启用任何示例节点。详见 [FULL-INSTALL.md](FULL-INSTALL.md)。

Both download entry points require the [v2.1.4 release assets](https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/releases/tag/v2.1.4) to be published. Each verifies its own SHA-256 manifest. Review scripts before running as root.

## Hardware requirements

- ZTE U60 Pro / MU5250, B31 vendor firmware family, OpenWrt 23.05.4, ARM64.
- Persistent writable /data; br-lan at 10.66.0.1; cellular rmnet_data0.
- iptables-legacy, ip6tables, iproute2, jsonfilter, /dev/net/tun.
- Direct LAN SSH access and sufficient storage. No firmware flashing, rooting, or Wi-Fi relay.

## Features

- IPv4 TCP REDIRECT and UDP TUN / XUDP, independent of mode number.
- Literal IPv6 single-node VLESS upstream with route preflight and ipv4_only DNS strategy.
- MAC-based TCP, DNS, UDP and IPv6 guard switches; direct clients retain their configured policy.
- Persistent mode names, create, clone, edit, format and validate JSON; automatic backups for edits.
- Delete offline device records; suppress stale DHCP rediscovery until positive rediscovery.
- Isolated U60PM_* chains; UDP policy table 167 with blackhole fallback.

## Management

Web UI: http://10.66.0.1:8081 — **trusted LAN only; no authentication**. Stock vendor ports 80/443 are not modified.

```sh
/data/proxy-mode/bin/proxy-mode status
/data/u60proxy/bin/u60proxy mode list
/data/u60proxy/bin/u60proxy udp-capable
ip -4 route show table 167
ip6tables -nvL U60PM_GUARD6
```

The IPv6 upstream feature is not dual-stack LAN interception. Keep IPv6 Guard enabled for full-proxy devices. Runtime guard counters and TUN readiness do not prove zero leakage. Chained IPv6 first-hop detection is not implemented. The new installer does not replace existing boot hooks.

## Documentation and safety

See [IPV6-UPSTREAM.md](IPV6-UPSTREAM.md), [UDP-CAPABILITY.md](UDP-CAPABILITY.md), and [FULL-INSTALL.md](FULL-INSTALL.md). Older incremental releases remain available for recovery. Do not upload real node addresses, UUIDs, keys, MACs, logs or private backups. This project is separate from the RAX3000M repository.
