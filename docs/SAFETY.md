# Safety

The reference U60 Pro firmware contains vendor firewall, modem, Wi-Fi and device-management logic that should remain intact.

Rules for this project:

1. Do not write firmware partitions.
2. Do not remount `/usr` writable.
3. Do not flush `iptables` tables.
4. Do not replace ZTE/QCOM firewall chains.
5. Keep transparent-proxy rules isolated and reversible.
6. Test process startup manually before adding any boot entry.
7. Keep ADB available during development as a recovery path.
8. Prefer public-key SSH. Do not enable password login for convenience.
9. Keep web control token private.
10. Never commit real proxy credentials or exported production mode files.

The initial installer deliberately does not modify firewall rules, `rc.local`, firmware partitions, or the stock ZTE web UI.
