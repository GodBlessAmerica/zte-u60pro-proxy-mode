# IPv6 upstream preview

Based on the v2.1.3 mode-independent UDP capability baseline. Existing compatible U60 Pro installations only.

## Architecture

IPv4 LAN TCP REDIRECT and UDP TUN/XUDP remain unchanged. A single VLESS Reality outbound may use a literal IPv6 server address. DNS strategy must be ipv4_only. The existing per-device IPv6 FORWARD guard remains separate from router-originated IPv6 connections. Direct devices can still use native IPv6 according to their policies.

## Existing-device installation

Download and extract the source archive from this branch, then run `sh install-ipv6-upstream.sh` over trusted LAN SSH. The installer preserves the existing sing-box and Go binaries, private profiles and device policies. It does not restart the active proxy.

Use configs/mode13-ipv6-upstream.example.json as a template for an unused mode number. Replace all placeholders locally, including the documentation-only IPv6 address. Do not upload production credentials.

## Verification

- Confirm a global IPv6 address and usable cellular IPv6 route.
- Validate the new profile with sing-box check.
- Select the new mode using the existing web UI or u60proxy mode set.
- Verify TCP, UDP, DNS and IPv6 leak behavior from a full-proxy client.
- Verify a direct client retains its intended policy.
- Switch back to an existing IPv4 VLESS mode, then back to IPv6.
- Verify cellular reconnection and router reboot recovery.

## Current validation status

Initial single-node IPv6 mode connectivity on U60 Pro has been reported successful by the device operator. UDP, leak prevention, switching regression and reboot recovery remain to be independently verified. No fresh-install claim is made. The readiness helper checks the final outbound only; chained IPv6 first hops are not covered. IPv6 upstream does not imply dual-stack LAN interception.

## Rollback

Run /data/u60proxy/bin/rollback-ipv6-upstream to restore the replaced scripts. Select the previous working profile if necessary. No credentials or runtime diagnostics are included in this repository.
