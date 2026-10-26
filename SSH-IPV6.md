# U60 Proxy 2.2.0：SSH-D IPv6 TCP 完整更新

这是从稳定主线重新实现的完整更新，不依赖已放弃的双栈 TUN 分支。

## 安装（已经装有 u60proxy 的 U60 Pro）

用 USB ADB 进入 U60 Pro shell，将下面整段复制执行。需要设备能通过 HTTPS 访问 GitHub。

```sh
curl -fL https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/feature/ssh-ipv6-complete/update-ssh-ipv6.sh -o /tmp/update-ssh-ipv6.sh && sh /tmp/update-ssh-ipv6.sh
```

没有 curl 时，先用 `wget -O /tmp/update-ssh-ipv6.sh` 下载同一地址，再 `sh /tmp/update-ssh-ipv6.sh`。
更新器下载完整 ARM64 安装包、校验 SHA256、备份并安装、重新启动当前模式及 8081 面板。不需要修改私人 JSON，不需要编译，不改变服务器密钥。

若设备无法下载 GitHub：电脑下载 Release 中的 `u60proxy-2.2.0-ssh-ipv6.tar.gz`，用 `adb push` 上传到 `/tmp/`，在设备上解压后运行目录内 `sh install-ssh-ipv6.sh`。

## 使用

打开 http://10.66.0.1:8081/，选择已有的 SSH Direct 模式。为需要代理的设备打开 TCP、DNS 和 IPv6 Guard；SSH 下建议关闭 UDP。
运行配置会自动添加 IPv6 TCP REDIRECT 入口，强制该入口经现有 SSH outbound。服务器有 IPv6 出口且 sshd 允许 TCP 转发时，IPv6 目标经服务器 IPv6 访问。到 SSH 服务器的连接仍可只用 IPv4。

自动识别依据是 `route.final` 对应的 outbound 类型为 `ssh`，不是模式编号。外部 `ssh -D` SOCKS 进程、SOCKS/selector/urltest final 不会被误识别为原生 SSH 模式。

需要客户端已经有可用的 IPv6 地址和到 U60 的 IPv6 路由。本版本不会为无 IPv6 的 LAN 自动创建 RA/DHCPv6 或虚拟 IPv6 地址；单有服务器 IPv6 不能替代客户端网络配置。
SSH 不承载普通 UDP/QUIC；受保护设备的 IPv6 UDP 继续由 Guard 阻断，支持回退的应用可改用 TCP。服务器没有 IPv6 时，IPv6 连接失败；双栈目标仍可用 IPv4。不使用运营商 IPv6 作为代理失败后的出口。

IPv6 Guard 必须保持开启：它会阻断未被接管的 IPv6 转发；被接管的 TCP 经本机 INPUT 进入 sing-box。非 SSH 模式沿用原有行为。
若固件缺少 IPv6 NAT/REDIRECT/mac/addrtype 模块，安装会报错并回退，不会自动安装内核模块或关闭 Guard。

## 诊断与回退

```sh
/data/proxy-mode/bin/proxy-mode status
ip6tables -t nat -S U60PM_SSH6
```

状态中的 `ssh_ipv6_config=on` 表示已生成入口配置，不代表远端 IPv6 连通性已探测成功。用浏览器访问 IPv6 测试站点确认实际出口。

```sh
B=$(cat /data/u60proxy-ssh6-last-backup)
sh "$B/rollback.sh" "$B"
```

备份包含旧程序、被改动脚本、原运行配置和私人配置快照。安装器不修改私人配置，因此回退也不覆盖安装后用户新编辑的私人配置。
安装失败时自动恢复旧文件并重新启动旧模式；昨天预览的 IPv6 开关会保持关闭，IPv6 Guard 保持 strict。
保留原 rc.local 启动入口。8081 使用单个进程，无循环扫描守护或新增持久日志。

## 验证范围

发布工作流执行 Go 测试、go vet、shell 语法检查和 Linux ARM64 交叉编译。
尚无 U60 Pro 实机流量验证，因此 Release 标记为 prerelease；不能将编译成功当作固件内核和网络路径已验证。
