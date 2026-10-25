# VLESS 双栈在线更新（已有安装）

不需要 ADB，不需要上传私人 JSON。GitHub 只存程序；U60 在本机读取现有 Mode 11，校验并备份后补齐 IPv6 配置，保留节点凭据和其他配置字段。
基于已安装的 u60proxy、sing-box 和可用的 VLESS Mode 11。服务器继续用兼容的 sing-box 1.14.0；不切回有握手冲突的 Xray 26.10.21。

## 1. 在 Azure 服务器 SSH 终端启用 IPv6 出口

```sh
curl --http1.1 -fL https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/feature/vless-dualstack-online/azure/enable-vless-ipv6.sh -o /tmp/enable-vless-ipv6.sh && sudo bash /tmp/enable-vless-ipv6.sh
```

先验证服务器原生 IPv6 出网，再备份并修改 direct 出口的域名解析策略。REALITY 握手目标仍通过 IPv4 解析。IP/端口/UUID/密钥保持不变。失败时恢复旧配置。
新建/重部署 Azure VM 使用 [azure/azure-vps-vless.sh](azure/azure-vps-vless.sh)：`AZ_VPS_PROXY_IPV6=on bash azure-vps-vless.sh deploy-vless`。新建双栈网络还要设置 `AZ_VPS_IPV6=on`。

## 2. 在 U60 root shell 在线更新

```sh
curl --http1.1 -fL https://raw.githubusercontent.com/GodBlessAmerica/zte-u60pro-proxy-mode/feature/vless-dualstack-online/update-vless-dualstack.sh -o /tmp/update-vless-dualstack.sh && sh /tmp/update-vless-dualstack.sh
```

没有 curl 时用 wget 下载同一 URL，再运行 sh。更新器下载完整 ARM64 发布包并校验 SHA256；本机转换现有 Mode 11 JSON，执行 sing-box check，备份、安装并激活 Mode 11。无需重编译面板。

在 8081 为测试设备开启 TCP、DNS、UDP、IPv6 Guard，重连 Wi-Fi。设备需已有 IPv6 地址和经 U60 的 IPv6 路由。

## 验证和回退

```sh
sh /data/u60-vless-dualstack/check.sh
sh /data/u60-vless-dualstack/rollback.sh
```

代理 IPv6 应为 Azure 出口（例如 2603:...），不能是本地运营商的 2408:...。脚本本地 SOCKS 测试验证远端 TCP 出口；手机浏览器和实际 UDP 应用还需分别验证 Wi-Fi 透明代理。

## 实现与范围

- IPv6 TCP 经 REDIRECT :7894；IPv6 UDP 经 mark 0x68/0xff、独立表 168 进入 u60udp0，保留 blackhole 默认路由。
- TUN 内部 IPv6 地址 fd75:60:0:168::1/126；按 MAC 和 TCP/UDP/IPv6 Guard 开关筛选。
- 不依赖固件缺少的 addrtype，不修改厂商表，不关闭 IPv6 Guard。
- traffic.sh 适配层调用原脚本；开机、模式切换、面板策略应用时自动重建规则。仅在带有双栈标记的 VLESS Mode 11 启用。
- 安装失败尝试自动回退。备份为 /data/u60-vless6-backup-*。
- 配置转换保留未知字段和凭据，重复更新不会重复添加入口、地址和规则。
- 本发布不改变 Mode 15 的现有 IPv4 UDP 自动处理限制，也不是全新空白设备安装器。

已执行配置校验、规则选择/失败清理和安装/回退模拟；发布工作流执行 Go 测试、go vet、真实 sing-box 1.14 配置校验和 ARM64 编译。尚待实际 U60 双栈 TCP/UDP 流量验证，因此标记为 prerelease。
