# Install

The current development installer is intentionally conservative. It copies project files to `/data` and does not enable transparent proxying or boot startup by itself.

## Prerequisites

- root shell through SSH or ADB
- writable `/data`
- isolated OpenUI dashboard server on port 8080 if web UI is desired
- an aarch64 sing-box binary supplied separately

## Install from source

```sh
cd /tmp
rm -rf zte-u60pro-proxy-mode-main u60proxy.tar.gz
wget -O u60proxy.tar.gz https://github.com/GodBlessAmerica/zte-u60pro-proxy-mode/archive/refs/heads/main.tar.gz
tar -xzf u60proxy.tar.gz
cd zte-u60pro-proxy-mode-main
sh install.sh
```

The installer prints the generated web control token. Keep it private.

## CLI

```sh
/data/proxy-mode/bin/proxy-mode preflight
/data/proxy-mode/bin/proxy-mode status
/data/proxy-mode/bin/proxy-mode list
/data/proxy-mode/bin/proxy-mode use 6
/data/proxy-mode/bin/proxy-mode start
/data/proxy-mode/bin/proxy-mode stop
/data/proxy-mode/bin/proxy-mode restart
```

## Dashboard

When the isolated OpenUI uhttpd server is available on port 8080:

```text
http://10.66.0.1:8080/proxy-mode/
```

Read-only status does not require the control token. Start/stop/restart actions require the token generated during installation.

## Not implemented yet

The first development milestone deliberately does not install transparent-routing firewall rules. TUN routing will be added only after device-specific routing and rollback behavior are validated.
