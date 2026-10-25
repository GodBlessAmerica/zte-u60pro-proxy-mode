#!/usr/bin/env bash
# Run on the existing Azure VM (sudo). Keep node credentials and service unit.
set -Eeuo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run with sudo bash'; exit 1; }
BASE=/etc/u60-vless
BIN=/usr/local/bin/u60-sing-box
[[ -x "$BIN" && -f "$BASE/config.json" && -f "$BASE/params.json" ]] || { echo 'Compatible sing-box VLESS installation required; deploy using azure/azure-vps-vless.sh first.'; exit 1; }
systemctl show u60-vless -p ExecStart --value | grep -Fq /usr/local/bin/u60-sing-box || { echo 'Service is not using the compatible sing-box core'; exit 1; }
V6=$(curl --http1.1 -6 -fsS --connect-timeout 10 --max-time 25 https://api64.ipify.org)
python3 - "$V6" <<'PY'
import ipaddress,sys
a=ipaddress.ip_address(sys.argv[1]);assert a.version==6 and a.is_global,'No global IPv6 egress'
print('Azure IPv6 egress verified: '+str(a))
PY
umask 077
BACKUP="$BASE/backup-ipv6-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP"
cp -p "$BASE/config.json" "$BACKUP/config.json"
cp -p "$BASE/params.json" "$BACKUP/params.json"
WORK=$(mktemp -d "$BASE/.enable-ipv6.XXXXXX")
CHANGED=0
finish(){
 rc=$?
 trap - EXIT
 if [[ "$CHANGED" == 1 ]]; then
   cp -p "$BACKUP/config.json" "$BASE/config.json"
   cp -p "$BACKUP/params.json" "$BASE/params.json"
   systemctl restart u60-vless || true
   echo 'Restored previous configuration after failed IPv6 activation' >&2
 fi
 rm -rf "$WORK"
 exit "$rc"
}
trap finish EXIT
python3 - "$BASE" "$WORK" <<'PY'
import json,pathlib,sys
b,w=map(pathlib.Path,sys.argv[1:])
c=json.loads((b/'config.json').read_text());p=json.loads((b/'params.json').read_text())
if not any(x.get('type')=='vless' for x in c.get('inbounds',[])):raise SystemExit('Not a sing-box VLESS config')
changed=False
for o in c.get('outbounds',[]):
 if o.get('type')=='direct' and o.get('tag')=='direct':
  resolver=o.get('domain_resolver')
  if not isinstance(resolver,dict) or not resolver.get('server'):raise SystemExit('Unsupported direct resolver; no settings changed')
  resolver['strategy']='prefer_ipv6';changed=True
if not changed:raise SystemExit('Expected direct outbound not found')
p['proxy_ipv6']=True
(w/'config.json').write_text(json.dumps(c,indent=2)+'\n')
(w/'params.json').write_text(json.dumps(p,indent=2)+'\n')
PY
"$BIN" check -c "$WORK/config.json"
chown --reference="$BASE/config.json" "$WORK/config.json"
chmod --reference="$BASE/config.json" "$WORK/config.json"
chmod 600 "$WORK/params.json"
CHANGED=1
mv "$WORK/config.json" "$BASE/config.json"
mv "$WORK/params.json" "$BASE/params.json"
systemctl restart u60-vless
sleep 2
systemctl is-active --quiet u60-vless
CHANGED=0
echo 'VLESS IPv4 + IPv6 server egress enabled. IPv4 ingress/UUID/keys/port unchanged.'
echo "Backup: $BACKUP"
echo 'Next: run the GitHub updater inside the U60 root shell.'
