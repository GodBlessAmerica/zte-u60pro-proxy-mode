#!/usr/bin/env bash
set -Eeuo pipefail
# Disposable Azure VM + sing-box VLESS REALITY Vision. U60-compatible server core.
# IPv6 dual stack is opt-in during creation. Existing UUID/keys are reused during migration.
RG="${AZ_VPS_RG:-rg-disposable-westus-vps}"
VM="${AZ_VPS_VM:-westus-vps}"
REGION="${AZ_VPS_REGION:-westus}"
SIZE="${AZ_VPS_SIZE:-Standard_B2ats_v2}"
IMAGE="${AZ_VPS_IMAGE:-Ubuntu2204}"
USER_NAME="${AZ_VPS_USER:-azureuser}"
KEY="${AZ_VPS_KEY:-$HOME/.ssh/azure_disposable_ed25519}"
IPV6="${AZ_VPS_IPV6:-off}"
OWNER_TAG="disposable-vps-script-v2"
VNET="${VM}-vnet"; SUBNET="${VM}-subnet"; NSG="${VM}-nsg"
NIC="${VM}-nic"; PIP4="${VM}-ipv4"; PIP6="${VM}-ipv6"

msg() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() { cat <<USAGE
Usage: $0 create | info | ssh | socks | test6 | delete
  create   Create one VM in its dedicated resource group (idempotent if already created)
  info     Show VM, resources, public IPv4 and IPv6
  ssh      SSH to the VM over IPv4
  socks    Start local SOCKS5 on 0.0.0.0:8889 over IPv4 SSH
  test6    Test IPv6 outbound HTTPS on the VM (requires SSH access)
  delete   Delete the ENTIRE selected resource group after confirmation
Options (environment variables):
  AZ_VPS_IPV6=on|off  Enable dual-stack when creating a NEW VM (default: off)
  AZ_VPS_RG, AZ_VPS_VM, AZ_VPS_REGION, AZ_VPS_SIZE,
  AZ_VPS_IMAGE, AZ_VPS_USER, AZ_VPS_KEY
Examples: 
  AZ_VPS_IPV6=on $0 create
  $0 info
  $0 socks
  $0 test6
  $0 delete
  AZ_VPS_RG=rg-vps-2 AZ_VPS_VM=vps-2 AZ_VPS_IPV6=on $0 create
  AZ_VPS_RG=rg-vps-2 AZ_VPS_VM=vps-2 $0 delete
Notes:
  Changing AZ_VPS_IPV6 after creation will not modify an existing VM.
  Resource group deletion removes all resources in that group, even manually added ones.
  SSH key remains on the local computer after deletion.
USAGE
}
need_az() {
  command -v az >/dev/null 2>&1 || fail 'Install Azure CLI first.'
  az account show --query id -o tsv >/dev/null 2>&1 || fail 'Azure login expired; run: az login'
}
exists() { az group exists --name "$RG" -o tsv; }
owner() { az group show -n "$RG" --query 'tags.disposableVpsManager' -o tsv 2>/dev/null || true; }
vm_exists() { az vm show -g "$RG" -n "$VM" --query id -o tsv >/dev/null 2>&1; }
ip4() {
  # For both original (auto-generated NIC) and new explicit dual-stack resources.
  az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv 2>/dev/null | tr ',' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true
}
ip6() {
  az network public-ip list -g "$RG" --query "[?publicIPAddressVersion=='IPv6'].ipAddress | [0]" -o tsv 2>/dev/null || true
}
ensure_key() {
  mkdir -p "$(dirname "$KEY")"
  chmod 700 "$(dirname "$KEY")" 2>/dev/null || true
  if [[ ! -e "$KEY" && ! -e "$KEY.pub" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$KEY" -C 'azure-disposable-vps'
    chmod 600 "$KEY"
  fi
  [[ -f "$KEY" && -f "$KEY.pub" ]] || fail "Incomplete key pair; will not overwrite: $KEY"
  ssh-keygen -y -f "$KEY" >/dev/null 2>&1 || fail "Cannot read private key: $KEY"
}
info() {
  local found; found=$(exists) || fail 'Cannot reach Azure to check group state.'
  if [[ "$found" != true ]]; then msg "Absent: $RG"; return; fi
  msg "Subscription: $(az account show --query name -o tsv)"
  msg "Group: $RG / Region: $REGION / Owner: $(owner)"
  az resource list -g "$RG" --query '[].{name:name,type:type}' -o table
  if vm_exists; then
    msg "Public IPv4: $(ip4)"
    msg "Public IPv6: $(ip6)"
    az vm get-instance-view -g "$RG" -n "$VM" --query 'instanceView.statuses[1].displayStatus' -o tsv || true
  else
    msg 'VM not found; resources may be partially created or being deleted.'
  fi
}
# Retry transient transport errors only; never reinterpret a failed read as absence.
az_retry() {
  local attempt rc err
  err=$(mktemp)
  for attempt in 1 2 3 4; do
    if az "$@" 2>"$err"; then cat "$err" >&2; rm -f "$err"; return 0; else rc=$?; fi
    cat "$err" >&2
    if ! grep -Eqi 'ConnectionResetError|Connection aborted|Connection reset|timed out|Timeout|temporarily unavailable|RemoteDisconnected' "$err"; then
      rm -f "$err"; return "$rc"
    fi
    msg "Azure connection interrupted; retry $attempt/4 (resources retained)." >&2
    sleep "$((attempt * 3))"
  done
  rm -f "$err"; return "$rc"
}
# Show first: only explicit ResourceNotFound permits creation. Unknown errors stop.
ensure_network_resource() {
  local kind="$1"; shift
  local -a prefix
  read -r -a prefix <<< "$kind"
  local err rc
  err=$(mktemp)
  if az_retry network "${prefix[@]}" show "$@" -o none 2>"$err"; then
    cat "$err" >&2; rm -f "$err"; msg "Reusing $kind"; return 0
  else rc=$?; fi
  if ! grep -Eqi 'ResourceNotFound|NotFound|could not be found|was not found' "$err"; then
    cat "$err" >&2; rm -f "$err"; return "$rc"
  fi
  rm -f "$err"
  return 10
}
network_step() {
  local kind="$1"; shift
  local -a identity create_args prefix
  read -r -a prefix <<< "$kind"
  while [[ "$1" != -- ]]; do identity+=("$1"); shift; done
  shift; create_args=("$@")
  local rc
  if ensure_network_resource "$kind" "${identity[@]}"; then return 0; else rc=$?; fi
  [[ "$rc" == 10 ]] || return "$rc"
  az_retry network "${prefix[@]}" create "${identity[@]}" "${create_args[@]}" -o none
}
wait_vm() {
  msg 'Waiting for VM provisioning (safe to rerun create if the connection fails)...'
  az_retry vm wait -g "$RG" -n "$VM" --created --interval 15 --timeout 900
}
create_dualstack() {
  # Azure IPv6 subnet is ULA; public IPv6 is attached to secondary NIC IP config.
  # Explicit dual-stack networking follows Microsoft Azure CLI guidance.
  network_step 'vnet' -g "$RG" -n "$VNET" -- -l "$REGION" --address-prefixes '10.250.0.0/16' 'fd00:250::/48' || return 1
  network_step 'vnet subnet' -g "$RG" --vnet-name "$VNET" -n "$SUBNET" -- --address-prefixes '10.250.0.0/24' 'fd00:250::/64' || return 1
  network_step 'nsg' -g "$RG" -n "$NSG" -- -l "$REGION" || return 1
  network_step 'nsg rule' -g "$RG" --nsg-name "$NSG" -n allow-ssh-ipv4 -- --priority 1000 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes '0.0.0.0/0' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 || return 1
  network_step 'public-ip' -g "$RG" -n "$PIP4" -- -l "$REGION" --sku Standard --allocation-method Static --version IPv4 || return 1
  network_step 'public-ip' -g "$RG" -n "$PIP6" -- -l "$REGION" --sku Standard --allocation-method Static --version IPv6 || return 1
  network_step 'nic' -g "$RG" -n "$NIC" -- -l "$REGION" --vnet-name "$VNET" --subnet "$SUBNET" --network-security-group "$NSG" --private-ip-address-version IPv4 --public-ip-address "$PIP4" || return 1
  network_step 'nic ip-config' -g "$RG" --nic-name "$NIC" -n ipconfig-ipv6 -- --vnet-name "$VNET" --subnet "$SUBNET" --private-ip-address-version IPv6 --public-ip-address "$PIP6" || return 1
  az_retry vm create -g "$RG" -n "$VM" -l "$REGION" --nics "$NIC" \
    --image "$IMAGE" --size "$SIZE" --admin-username "$USER_NAME" \
    --authentication-type ssh --ssh-key-values "$KEY.pub" \
    --storage-sku StandardSSD_LRS --os-disk-size-gb 30 \
    --os-disk-delete-option Delete --no-wait -o none || return 1
  wait_vm
}
create_vm() {
  local found; found=$(az_retry group exists --name "$RG" -o tsv) || fail 'Cannot reach Azure; no changes made.'
  if [[ "$found" == true ]]; then
    [[ "$(owner)" == "$OWNER_TAG" ]] || fail "Group $RG exists but is not script-owned."
    local vm_count
    vm_count=$(az_retry vm list -g "$RG" --query "length([?name=='$VM'])" -o tsv) || fail 'Cannot verify VM state. No creation attempted.'
    if [[ "$vm_count" == 1 ]]; then wait_vm || fail 'VM not ready; rerun create later.'; return; fi
    [[ "$IPV6" == on ]] || fail 'Partial deployment found. Resume with AZ_VPS_IPV6=on, or inspect info.'
    msg 'Resuming the script-owned dual-stack deployment.' 
  fi
  [[ "$IPV6" == on || "$IPV6" == off ]] || fail 'AZ_VPS_IPV6 must be on or off.'
  ensure_key
  msg "Subscription: $(az account show --query name -o tsv)"
  msg "Creating VM=$VM region=$REGION size=$SIZE IPv6=$IPV6 key=$KEY"
  az_retry group create -n "$RG" -l "$REGION" --tags "disposableVpsManager=$OWNER_TAG" -o none
  if [[ "$IPV6" == on ]]; then
    # Failure exits without deleting resources automatically: investigate billable partial deployments.
    if ! create_dualstack; then
      msg "Creation failed. Resources may remain and incur charges. Rerun the same create command to resume; use info to inspect."
      exit 1
    fi
  else
    if ! az vm create -g "$RG" -n "$VM" -l "$REGION" \
      --image "$IMAGE" --size "$SIZE" --admin-username "$USER_NAME" \
      --authentication-type ssh --ssh-key-values "$KEY.pub" \
      --storage-sku StandardSSD_LRS --os-disk-size-gb 30 \
      --os-disk-delete-option Delete --public-ip-sku Standard --nsg-rule SSH -o none; then
      msg "Creation failed. Resources may remain and incur charges. Rerun the same create command to resume; use info to inspect."
      exit 1
    fi
  fi
  msg "SUCCESS. IPv4: $(ip4) / IPv6: $(ip6)"
  msg "SSH: $0 ssh / SOCKS5: $0 socks / IPv6 test: $0 test6 / DELETE: $0 delete"
}
ssh_connect() {
  [[ -f "$KEY" ]] || fail "Missing SSH private key: $KEY"
  vm_exists || fail 'VM missing. Run info/create.'
  local address; address=$(ip4)
  [[ -n "$address" ]] || fail 'No public IPv4 address assigned.'
  msg "Connecting to $USER_NAME@$address (new VM may need time for SSH startup)."
  if [[ "${1:-}" == socks ]]; then
    exec ssh -4 -N -D 0.0.0.0:8889 -i "$KEY" -o IdentitiesOnly=yes \
      -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      -o StrictHostKeyChecking=accept-new "$USER_NAME@$address"
  fi
  if [[ "${1:-}" == test6 ]]; then
    ssh -4 -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
      "$USER_NAME@$address" 'echo "IPv6 addresses:"; ip -6 -br addr; echo "IPv6 route:"; ip -6 route; echo "Outbound IPv6:"; curl -6 -fsS --max-time 15 https://api64.ipify.org; echo' 
    return
  fi
  exec ssh -4 -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "$USER_NAME@$address"
}
delete_all() {
  local found; found=$(exists) || fail 'Cannot check Azure state.'
  if [[ "$found" != true ]]; then msg "Already absent: $RG"; return; fi
  [[ "$(owner)" == "$OWNER_TAG" ]] || fail "Refusing to delete non-script-owned resource group: $RG"
  msg "Subscription: $(az account show --query name -o tsv)"
  msg "WARNING: Deletes ALL resources inside $RG, including manually added resources."
  az resource list -g "$RG" --query '[].{name:name,type:type}' -o table || true
  local confirm
  read -r -p "Type '$RG' to confirm permanent deletion: " confirm
  [[ "$confirm" == "$RG" ]] || { msg 'Cancelled.'; return; }
  if ! az group delete -n "$RG" --yes --no-wait -o none; then
    msg 'Request failed/interrupted; remote deletion MAY already be underway. Verify in portal.'
    exit 1
  fi
  msg 'Deletion accepted. Verifying resource group disappearance...'
  local i state
  for ((i=1;i<=120;i++)); do
    if state=$(exists 2>/dev/null); then
      if [[ "$state" == false ]]; then
        msg "CONFIRMED DELETED: $RG. Local SSH key retained: $KEY"
        return
      fi
    else
      msg "Cannot verify deletion now. Retry '$0 info' when connectivity returns."
      exit 1
    fi
    sleep 5
  done
  msg "Deletion still processing; check '$0 info' and portal."
  exit 1
}
# VLESS additions: existing Azure lifecycle and resource ownership checks retained.
VLESS_PORT="${AZ_VPS_VLESS_PORT:-443}"
VLESS_SNI="${AZ_VPS_VLESS_SNI:-www.tesla.com}"
SING_BOX_VERSION=1.14.0
PROXY_IPV6="${AZ_VPS_PROXY_IPV6:-off}"
OUT_ROOT="${AZ_VPS_OUTPUT_DIR:-$HOME/.local/share/azure-vps-vless}"
require_tools() {
  [[ "$PROXY_IPV6" == on || "$PROXY_IPV6" == off ]] || fail 'AZ_VPS_PROXY_IPV6 must be on or off.'
  command -v python3 >/dev/null || fail 'Install python3 first.'
  [[ "$VLESS_PORT" =~ ^[0-9]+$ ]] && ((10#$VLESS_PORT >= 1 && 10#$VLESS_PORT <= 65535)) || fail 'Invalid VLESS port.'
  [[ "$VLESS_PORT" != 22 ]] || fail 'VLESS port must not be SSH port 22.'
  [[ "$VLESS_SNI" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || fail 'SNI must be a hostname.'

}
owned_vm() {
  [[ "$(owner)" == "$OWNER_TAG" ]] || fail 'Resource group is not owned by this script.'
  vm_exists || fail 'VM missing. Run create first.'
}
output_directory() {
  local sub
  sub=$(az account show --query id -o tsv)
  python3 - "$OUT_ROOT" "$sub" "$RG" "$VM" <<'PY'
import hashlib,pathlib,sys
key=hashlib.sha256('\0'.join(sys.argv[2:]).encode()).hexdigest()[:16]
print(pathlib.Path(sys.argv[1]).expanduser().resolve()/key)
PY
}
allow_vless_port() {
  local nic_id nsg_id
  nic_id=$(az vm show -g "$RG" -n "$VM" --query 'networkProfile.networkInterfaces[0].id' -o tsv)
  nsg_id=$(az network nic show --ids "$nic_id" --query 'networkSecurityGroup.id' -o tsv)
  [[ -n "$nsg_id" && "$nsg_id" != None ]] || fail 'NIC has no NSG; configure one before deploying.'
  # TCP 443 carries both proxied TCP and XUDP; no public UDP listener is required.
  az network nsg rule create -g "$RG" --nsg-name "${nsg_id##*/}" -n allow-u60-vless \
    --priority 1010 --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes '0.0.0.0/0' --source-port-ranges '*' \
    --destination-address-prefixes '*' --destination-port-ranges "$VLESS_PORT" -o none
}
write_bootstrap() {
  python3 - "$1" "$VLESS_PORT" "$VLESS_SNI" "$SING_BOX_VERSION" "$PROXY_IPV6" <<'PY'
import pathlib,shlex,sys
body=r'''
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
umask 077
BASE=/etc/u60-vless
BIN=/usr/local/bin/u60-sing-box
if command -v cloud-init >/dev/null; then cloud-init status --wait >/dev/null 2>&1 || true; fi
if [ -e "$BASE" ] && [ ! -f "$BASE/managed-by-azure-vps-vless" ]; then echo 'Unmanaged config directory exists' >&2; exit 1; fi
mkdir -p "$BASE"
touch "$BASE/managed-by-azure-vps-vless"
apt-get -o DPkg::Lock::Timeout=180 update -qq >/dev/null
apt-get -o DPkg::Lock::Timeout=180 install -y -qq ca-certificates curl unzip openssl python3 >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
case "$(uname -m)" in x86_64) ARCH=64;; aarch64) ARCH=arm64-v8a;; *) echo 'Unsupported architecture' >&2; exit 1;; esac
case "$ARCH" in
  64) SBARCH=amd64; SHA=2375de6999f4f56ab46b4fc5ddf26a6aba1d3e61a0f4e7ddec2f4690457d5f63;;
  arm64-v8a) SBARCH=arm64; SHA=04d9b40bc98dc55b6f509ce3292145c65478f65866bea64826ebb2f382385088;;
esac
URL="https://github.com/SagerNet/sing-box/releases/download/v$VERSION/sing-box-$VERSION-linux-$SBARCH.tar.gz"
curl --http1.1 -fLsS --retry 3 --connect-timeout 20 --max-time 180 "$URL" -o "$TMP/sing-box.tar.gz"
printf '%s  %s\n' "$SHA" "$TMP/sing-box.tar.gz" | sha256sum -c - >/dev/null
tar -xzf "$TMP/sing-box.tar.gz" -C "$TMP"
cp "$TMP/sing-box-$VERSION-linux-$SBARCH/sing-box" "$TMP/sing-box"
chmod 755 "$TMP/sing-box"
# Refuse to bind over unrelated listeners. Existing managed service may keep its port.
if [ ! -f "$BASE/params.json" ] && ss -H -lnt "sport = :$PORT" | grep -q .; then echo "Port $PORT is already occupied" >&2; exit 1; fi
if [ "$PROXY_IPV6" = on ]; then
  V6_TEST=$(curl --http1.1 -6 -fsS --connect-timeout 10 --max-time 20 https://api64.ipify.org)
  case "$V6_TEST" in *:*) echo "IPv6 egress verified: $V6_TEST";; *) echo 'IPv6 egress test failed; old service retained' >&2; exit 1;; esac
fi
python3 - "$BASE" "$PORT" "$SNI" "$PROXY_IPV6" <<'CONFIG'
import base64,json,pathlib,secrets,subprocess,sys,uuid
b=pathlib.Path(sys.argv[1]);port=int(sys.argv[2]);sni=sys.argv[3];v6=sys.argv[4]=='on'
p=b/'params.json'
if p.exists():
 data=json.loads(p.read_text())
 if data['port']!=port or data['sni']!=sni:raise SystemExit('Existing deployment uses different port/SNI. Reuse original settings.')
else:
 pem=subprocess.check_output(['openssl','genpkey','-algorithm','X25519'])
 private=subprocess.run(['openssl','pkey','-outform','DER'],input=pem,check=True,stdout=subprocess.PIPE).stdout[-32:]
 public=subprocess.run(['openssl','pkey','-pubout','-outform','DER'],input=pem,check=True,stdout=subprocess.PIPE).stdout[-32:]
 enc=lambda x:base64.urlsafe_b64encode(x).decode().rstrip('=')
 data={'port':port,'sni':sni,'uuid':str(uuid.uuid4()),'private_key':enc(private),'public_key':enc(public),'short_id':secrets.token_hex(8)}
 p.write_text(json.dumps(data,indent=2)+'\n');p.chmod(0o600)
cfg={'log':{'level':'warn','timestamp':True},'dns':{'servers':[{'type':'local','tag':'local-dns'}]},'inbounds':[{'type':'vless','tag':'vless-in','listen':'0.0.0.0','listen_port':port,'users':[{'uuid':data['uuid'],'flow':'xtls-rprx-vision'}],'tls':{'enabled':True,'server_name':sni,'reality':{'enabled':True,'handshake':{'server':sni,'server_port':443,'domain_resolver':{'server':'local-dns','strategy':'ipv4_only'}},'private_key':data['private_key'],'short_id':[data['short_id']]}}}],'outbounds':[{'type':'direct','tag':'direct','domain_resolver':{'server':'local-dns','strategy':'prefer_ipv6' if v6 else 'ipv4_only'}}],'route':{'final':'direct'}}
(b/'config.new.json').write_text(json.dumps(cfg,indent=2)+'\n')
data['proxy_ipv6']=v6
(b/'params.pending.json').write_text(json.dumps(data,indent=2)+'\n')
CONFIG
"$TMP/sing-box" check -c "$BASE/config.new.json" >/dev/null
# Check REALITY target TLS1.3 reachability before activating service.
timeout 20 openssl s_client -4 -connect "$SNI:443" -servername "$SNI" -tls1_3 </dev/null > "$TMP/tls-test" 2>&1
grep -q 'TLSv1.3' "$TMP/tls-test" || { echo 'REALITY target TLS1.3 check failed' >&2; exit 1; }
id u60vless >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin u60vless
chown root:u60vless "$BASE"
chmod 750 "$BASE"
[ ! -f "$BASE/config.json" ] || cp -p "$BASE/config.json" "$BASE/config.previous.json"
install -m 755 "$TMP/sing-box" "$BIN.new"
mv -f "$BIN.new" "$BIN"
mv "$BASE/config.new.json" "$BASE/config.json"
chown root:u60vless "$BASE/config.json"
chmod 640 "$BASE/config.json"
[ ! -f /etc/systemd/system/u60-vless.service ] || cp -p /etc/systemd/system/u60-vless.service \
  "$BASE/u60-vless.service.previous"
cat > /etc/systemd/system/u60-vless.service <<'SERVICE'
[Unit]
Description=Azure disposable VLESS REALITY Vision
Wants=network-online.target
After=network-online.target
[Service]
User=u60vless
Group=u60vless
ExecStart=/usr/local/bin/u60-sing-box run -c /etc/u60-vless/config.json
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
SERVICE
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow "$PORT/tcp" >/dev/null; fi
systemctl daemon-reload
systemctl enable u60-vless >/dev/null
systemctl restart u60-vless
sleep 2
if ! systemctl is-active --quiet u60-vless; then
  journalctl -u u60-vless -n 20 --no-pager >&2
  if [ -f "$BASE/config.previous.json" ] && [ -f "$BASE/u60-vless.service.previous" ]; then
    cp -p "$BASE/config.previous.json" "$BASE/config.json"
    cp -p "$BASE/u60-vless.service.previous" /etc/systemd/system/u60-vless.service
    systemctl daemon-reload
    systemctl restart u60-vless || true
    echo 'Previous service/config restored after failed migration' >&2
  fi
  exit 1
fi
ss -H -lnt "sport = :$PORT" | grep -q . || { echo 'Listener did not start' >&2; exit 1; }
mv "$BASE/params.pending.json" "$BASE/params.json"
chmod 600 "$BASE/params.json"
python3 - "$BASE/params.json" <<'EXPORT'
import base64,json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text());p.pop('private_key')
print('U60_VLESS_EXPORT='+base64.b64encode(json.dumps(p).encode()).decode())
EXPORT
'''
prefix='#!/bin/sh\nexec /bin/bash <<\'U60_REMOTE_BOOTSTRAP\'\n'
prefix+='PORT='+shlex.quote(sys.argv[2])+'\nSNI='+shlex.quote(sys.argv[3])+'\nVERSION='+shlex.quote(sys.argv[4])+'\nPROXY_IPV6='+shlex.quote(sys.argv[5])+'\n'
pathlib.Path(sys.argv[1]).write_text(prefix+body+'\nU60_REMOTE_BOOTSTRAP\n')
PY
}
export_client() {
  python3 - "$1" "$2" "$3" <<'PY'
import base64,ipaddress,json,os,pathlib,re,sys,urllib.parse
result=json.loads(pathlib.Path(sys.argv[1]).read_text())
messages='\n'.join(v.get('message','') for v in result.get('value',[]))
matches=re.findall(r'^U60_VLESS_EXPORT=([A-Za-z0-9+/=]+)\s*$',messages,re.M)
if not matches:
 print(messages[-6000:],file=sys.stderr)
 raise SystemExit('Deployment did not return verified node parameters. VM remains; retry deploy-vless or inspect info.')
p=json.loads(base64.b64decode(matches[-1]));ip=str(ipaddress.IPv4Address(sys.argv[2]));out=pathlib.Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True);out.chmod(0o700)
tag='mode11-vless'
cfg={'log':{'level':'info','timestamp':True},'dns':{'servers':[{'type':'https','tag':'dns-remote','server':'1.1.1.1','server_port':443,'path':'/dns-query','tls':{'enabled':True,'server_name':'cloudflare-dns.com'},'detour':tag}],'strategy':'ipv4_only'},'inbounds':[{'type':'redirect','tag':'tcp-redirect-in','listen':'0.0.0.0','listen_port':7893},{'type':'tun','tag':'udp-tun-in','interface_name':'u60udp0','address':['172.31.255.1/30'],'mtu':1300,'auto_route':False,'strict_route':False,'stack':'system'},{'type':'direct','tag':'dns4-proxy-in','listen':'0.0.0.0','listen_port':5353,'override_address':'1.1.1.1','override_port':53},{'type':'direct','tag':'dns6-proxy-in','listen':'::','listen_port':5354,'override_address':'1.1.1.1','override_port':53}],'outbounds':[{'type':'vless','tag':tag,'server':ip,'server_port':p['port'],'uuid':p['uuid'],'flow':'xtls-rprx-vision','packet_encoding':'xudp','tls':{'enabled':True,'server_name':p['sni'],'utls':{'enabled':True,'fingerprint':'chrome'},'reality':{'enabled':True,'public_key':p['public_key'],'short_id':p['short_id']}}},{'type':'direct','tag':'direct'}],'route':{'auto_detect_interface':True,'rules':[{'action':'sniff'},{'inbound':['dns4-proxy-in','dns6-proxy-in'],'action':'hijack-dns'},{'ip_is_private':True,'action':'route','outbound':'direct'}],'final':tag}}
if p.get('proxy_ipv6',False):
 # Client DNS stays IPv4-only even when the server has IPv6 egress.
 cfg['inbounds'].insert(1,{'type':'redirect','tag':'vless6-redirect-in','listen':'::','listen_port':7894})
 for ib in cfg['inbounds']:
  if ib['type']=='tun':ib['address'].append('fd75:60:0:168::1/126')
 cfg['route']['rules'].insert(0,{'inbound':['vless6-redirect-in'],'action':'route','outbound':tag})
q=urllib.parse.urlencode({'encryption':'none','security':'reality','sni':p['sni'],'fp':'chrome','pbk':p['public_key'],'sid':p['short_id'],'type':'tcp','flow':'xtls-rprx-vision'})
uri=f"vless://{p['uuid']}@{ip}:{p['port']}?{q}#Azure-U60-VLESS"
def save(name,text):
 f=out/name;tmp=out/(name+'.tmp');tmp.write_text(text);tmp.chmod(0o600);os.replace(tmp,f)
save('mode11.json',json.dumps(cfg,ensure_ascii=False,indent=2)+'\n')
save('vless.txt',uri+'\n');save('node-parameters.json',json.dumps({'server':ip,**p},indent=2)+'\n')
print('Guest deployment verified. Proxy IPv6: '+str(p.get('proxy_ipv6',False)))
if p.get('proxy_ipv6',False):print('Install the U60 VLESS dual-stack adapter before activating this mode11.json. Keep IPv6 Guard ON.')
print('Files: '+str(out));print('Use mode11.json with existing U60 Mode 11 for automatic UDP routing.')
print('Client DNS: ipv4_only. Only mode11.json is generated; old local mode15.json files are not modified.')
print('VLESS link:\n'+uri)
PY
}
deploy_vless() {
  require_tools
  owned_vm
  local address outdir work
  address=$(ip4); [[ -n "$address" ]] || fail 'No public IPv4 assigned.'
  outdir=$(output_directory)
  mkdir -p "$outdir"; chmod 700 "$outdir"
  work=$(mktemp -d)
  write_bootstrap "$work/bootstrap.sh"
  msg 'Deploying VLESS through Azure VM Agent (usually a few minutes)...'
  # Run Command avoids SSH startup races and reused-IP host-key conflicts.
  if ! az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
      --scripts "$(cat "$work/bootstrap.sh")" -o json > "$work/result.json"; then
    rm -rf "$work"; fail 'Azure deployment command failed. VM is retained. Retry deploy-vless; info/delete remain available.'
  fi
  if ! export_client "$work/result.json" "$address" "$outdir"; then
    rm -rf "$work"; fail 'VLESS deployment failed. VM remains billable. Retry deploy-vless or use delete.'
  fi
  rm -rf "$work"
  allow_vless_port || fail 'Service deployed, but NSG rule failed. Retry deploy-vless to finish opening the port.'
  # This only checks TCP reachability, not an authenticated VLESS handshake.
  if python3 - "$address" "$VLESS_PORT" <<'PY'
import socket,sys
try:
 s=socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=10);s.close()
except OSError as e:print('TCP port probe: '+str(e),file=sys.stderr);sys.exit(1)
PY
  then msg "Public TCP $address:$VLESS_PORT reachable. Import config to verify end-to-end traffic."
  else msg 'Public TCP probe failed; NSG propagation, local network blocking or a subnet NSG may be involved. Do not treat this as verified end-to-end connectivity.'; return 1; fi
}
vless_info() {
  owned_vm
  local address outdir work
  address=$(ip4);outdir=$(output_directory);work=$(mktemp -d)
  if ! az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts \
    "python3 -c 'import json,base64; p=json.load(open(\"/etc/u60-vless/params.json\")); p.pop(\"private_key\"); print(\"U60_VLESS_EXPORT=\"+base64.b64encode(json.dumps(p).encode()).decode())'" -o json > "$work/result.json"; then rm -rf "$work"; fail 'Could not retrieve node parameters.'; fi
  local rc=0
  export_client "$work/result.json" "$address" "$outdir" || rc=$?
  rm -rf "$work"
  return "$rc"
}
usage_vless() {
  cat <<'HELP'
Usage: bash azure-vps-vless.sh create|deploy-vless|vless-info|info|ssh|socks|test6|delete
  create        Create/reuse the script-owned VM, then deploy VLESS REALITY Vision.
                Compatibility fix: server uses sing-box 1.14.0, not Xray 26.10.21.
  deploy-vless  Install/retry on an existing script-owned VM; preserve credentials.
  vless-info    Retrieve current credentials and regenerate local JSON/link files.
  info          Show Azure resources and public IPs.
  ssh/socks/test6/delete retain their original meanings.
Options:
  AZ_VPS_VLESS_PORT=443
  AZ_VPS_VLESS_SNI=www.tesla.com
  Server core: sing-box 1.14.0 (pinned and SHA256 verified for U60 compatibility).
  AZ_VPS_OUTPUT_DIR=$HOME/.local/share/azure-vps-vless
  AZ_VPS_IPV6=off (Azure networking during creation only)
  AZ_VPS_PROXY_IPV6=on|off (default off; on verifies server IPv6 then exports dual-stack JSON)
  Original AZ_VPS_RG/VM/REGION/SIZE/IMAGE/USER/KEY options are preserved.
Outputs: mode11.json (DNS ipv4_only), vless.txt, node-parameters.json.
  No Mode 15 output. Existing local mode15.json files are left untouched.
Run on Linux/WSL/macOS with Azure CLI and python3; az login first.
Needs VM Agent Run Command permissions and HTTPS download access in the guest.
delete removes the entire owned resource group after confirmation; local keys and exports remain.
HELP
}
main() {
  case "${1:-}" in -h|--help|help|'') usage_vless; return;; create|deploy-vless|vless-info|info|ssh|socks|test6|delete) ;; *) usage_vless; exit 2;; esac
  need_az
  case "$1" in
    create) require_tools; create_vm; deploy_vless;;
    deploy-vless) deploy_vless;; vless-info) require_tools; vless_info;;
    info) info;; ssh) ssh_connect ssh;; socks) ssh_connect socks;; test6) ssh_connect test6;; delete) delete_all;;
  esac
}
if [[ "${AZ_VPS_TEST_SOURCE_ONLY:-0}" != 1 ]]; then main "$@"; fi
