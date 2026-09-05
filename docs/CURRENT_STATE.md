# Current State — 2.1.2

Validated on ZTE U60 Pro / MU5250 B31.

## Passed

- Mode 11 TCP REDIRECT path
- Mode 11 UDP TUN/XUDP path
- UDP policy table 167 with blackhole fail-closed fallback
- Per-device TCP, DNS, UDP and IPv6 policy files
- MAC-keyed persistent device policy
- Web control plane on 10.66.0.1:8081
- Online detection using Wi-Fi association + br-lan neighbor state
- Mode JSON editor on the 8081 control panel
- JSON syntax validation and `sing-box check` before mode-config replacement
- Timestamped backup of the previous mode JSON before saving
- rc.local boot recovery for proxy core and web control plane
- Reboot recovery after full device restart
- `u60proxy doctor` with fail=0 / warn=0 on the validated installation

## Known behavior / open validation

Mode 11 is the validated UDP-capable mode. Modes without a UDP-capable path should not be treated as providing UDP proxy merely because a device policy has UDP enabled.

Mode 5 (SSH Direct), Mode 6 (SSH -> SOCKS5), and Mode 7 (SSH Jump) depend on SSH server-side forwarding policy and are not currently considered fully validated. In testing, Mode 5 reached the sing-box SSH outbound but the SSH server rejected destination forwarding with `ssh: rejected: connect failed (Connection refused)`. This is an upstream SSH forwarding/service condition, not a failure of the U60 TCP REDIRECT capture path.

Mode 10 TPROXY is deprecated and retained only for history/reference.

The 8081 control panel currently has no login authentication. Because mode JSON files may contain private server details, the editor should only be used on a trusted LAN.

## Not included

Wi-Fi relay / upstream STA mode is deliberately excluded from 2.1.2. It will be developed as a separate module after the stable proxy core is frozen.
