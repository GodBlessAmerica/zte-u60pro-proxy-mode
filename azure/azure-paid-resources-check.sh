#!/usr/bin/env bash
# Azure ARM inventory: read-only; not a zero-billing certificate.
set -Eeuo pipefail
RG="${AZ_VPS_RG:-rg-disposable-westus-vps}"
command -v az >/dev/null || { echo '🔴 未安装 Azure CLI' >&2; exit 2; }
command -v python3 >/dev/null || { echo '🔴 未安装 Python 3' >&2; exit 2; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
az account show -o json > "$TMP/account.json" || { echo '🔴 Azure 登录失败，请运行 az login' >&2; exit 2; }
az group list -o json > "$TMP/groups.json" || { echo '🔴 资源组查询失败' >&2; exit 2; }
az resource list -o json > "$TMP/resources.json" || { echo '🔴 ARM 资源查询失败' >&2; exit 2; }
python3 - "$TMP" "$RG" <<'PY'
import json,os,sys
from pathlib import Path
p=Path(sys.argv[1]); target=sys.argv[2]
a=json.loads((p/'account.json').read_text())
groups=json.loads((p/'groups.json').read_text())
resources=json.loads((p/'resources.json').read_text())
colors=sys.stdout.isatty() and not os.getenv('NO_COLOR')
def status(symbol,msg,color=''):
    c={'green':'\033[32m','yellow':'\033[33m','red':'\033[31m'}.get(color,'') if colors else ''
    print(c+symbol+' '+msg+('\033[0m' if c else ''))
print('\n====== Azure 资源检查（只读）======')
print('订阅：'+a.get('name','未知'))
g=next((x for x in groups if x['name'].lower()==target.lower()),None)
owned=[x for x in groups if (x.get('tags') or {}).get('disposableVpsManager')=='disposable-vps-script-v2']
if g: status('🟡',f'目标资源组仍存在：{target}（{g.get("properties",{}).get("provisioningState","未知")}）','yellow')
else: status('🟢',f'目标资源组不存在：{target}','green')
if owned: status('🟡','脚本管理资源组：'+', '.join(x['name'] for x in owned),'yellow')
else: status('🟢','脚本管理资源组：0 个','green')
others=[]
for x in resources:
    if x.get('type','').lower()=='microsoft.network/networkwatchers':
        status('🟡',f'Network Watcher：{x.get("name","")}（本身通常免费，相关功能可能收费）','yellow')
    else: others.append(x)
if others:
    status('🔴',f'其他可见 ARM 资源：{len(others)} 个，需人工核查','red')
    for x in others: print('  -',x.get('resourceGroup',''),x.get('type',''),x.get('name',''))
else: status('🟢','除 Network Watcher 外，没有其他可见 ARM 资源','green')
if not g and not owned and not others: status('🟢','VPS 清理检查通过','green')
else: status('🟡','仍有待检查资源','yellow')
status('⚪','账单未核实：历史费用、软删除备份、预留实例、Marketplace 等需单独检查')
print('范围：当前 Azure CLI 所选订阅与当前身份可见资源；未修改任何资源。')
PY
