# Current State — 2.1.1

Validated on ZTE U60 Pro / MU5250 B31.

## Passed

- Mode 11 TCP REDIRECT path
- Mode 11 UDP TUN/XUDP path
- UDP policy table 167 with blackhole fail-closed fallback
- Per-device TCP, DNS, UDP and IPv6 policy files
- MAC-keyed persistent device policy
- Web control plane on 10.66.0.1:8081
- Online detection using Wi-Fi association + br-lan neighbor state
- rc.local boot recovery for proxy core and web control plane
- Reboot recovery after full device restart
- `u60proxy doctor` with fail=0 / warn=0 on the validated installation

## Known behavior

Mode 11 is the validated UDP-capable mode. Modes without a UDP-capable path should not be treated as providing UDP proxy merely because a device policy has UDP enabled.

Mode 10 TPROXY is deprecated and retained only for history/reference.

## Not included

Wi-Fi relay / upstream STA mode is deliberately excluded from 2.1.1. It will be developed as a separate module after the stable proxy core is frozen.
