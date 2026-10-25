#!/usr/bin/env bash
# Read-only inventory. No deletion, no account switching, no billing guarantee.
set -Eeuo pipefail
command -v az >/dev/null || { echo 'Install Azure CLI first.' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'Install python3 first.' >&2; exit 2; }
export AZURE_CORE_COLLECT_TELEMETRY=no
python3 - "${AZ_VPS_RG:-rg-disposable-westus-vps}" "$@" <<'PY'
import json, subprocess, sys, time
rg=sys.argv[1]
args=sys.argv[2:]
if args and args[0] in ('--help','-h'):
 print('Usage: bash azure-paid-resources-check.sh [--subscription ID]')
 print('Default: inspect all accessible subscriptions returned by az account list --all --refresh.')
 print('AZ_VPS_RG selects the disposable resource group to check. No resources are changed.')
 sys.exit(0)
if args and (len(args)!=2 or args[0]!='--subscription'):
 sys.exit('Expected --subscription ID, or no arguments')

def run(argv):
 for attempt in range(3):
  try:
   p=subprocess.run(['az',*argv,'-o','json','--only-show-errors'],capture_output=True,text=True,timeout=120)
  except subprocess.TimeoutExpired:
   error='Azure CLI request timed out'
  else:
   if p.returncode==0:
    try:return json.loads(p.stdout)
    except ValueError:raise RuntimeError('Invalid JSON from Azure CLI')
   error=p.stderr.strip()
   if not any(x in error.lower() for x in ('connection','timeout','timed out','temporarily','429')):
    raise RuntimeError(error)
  if attempt<2:time.sleep(3*(attempt+1))
 raise RuntimeError(error)
try: subs=run(['account','list','--all','--refresh'])
except RuntimeError as e:sys.exit('INCOMPLETE: cannot list subscriptions; run az login if needed. '+str(e))
if args:
 subs=[s for s in subs if s['id'].lower()==args[1].lower()]
 if not subs:sys.exit('INCOMPLETE: requested subscription is not accessible')
if not subs:sys.exit('INCOMPLETE: no accessible subscriptions')
unknown=False;remaining=0
# These are candidates, NOT a tariff determination. Print ALL other resources too.
risk=('virtualmachines','disks','snapshots','images','publicipaddresses','natgateways','loadbalancers','bastionhosts','virtualnetworkgateways','storageaccounts','vaults','serverfarms','managedclusters','workspaces','servers','databases','registries','containerapps','managedenvironments','privatednszones','dnszones','privateendpoints','expressroutecircuits','firewalls','ddosprotectionplans')
for sub in subs:
 sid=sub['id']; print('\n=== Subscription: %s / %s / %s ==='%(sub['name'],sid,sub.get('state','unknown')),flush=True)
 try:
  groups=run(['group','list','--subscription',sid])
  resources=run(['resource','list','--subscription',sid])
 except RuntimeError as e:
  unknown=True;print('INCOMPLETE: '+str(e));continue
 target=[g for g in groups if g['name'].lower()==rg.lower()]
 if target:
  print('TARGET GROUP EXISTS: '+rg+' state='+str(target[0].get('properties',{}).get('provisioningState','unknown')))
 else:print('TARGET GROUP ABSENT: '+rg)
 owned=[g['name'] for g in groups if (g.get('tags') or {}).get('disposableVpsManager')=='disposable-vps-script-v2']
 print('Script-owned groups: '+(', '.join(owned) or 'none'))
 remaining+=len(resources)
 if not resources:print('NO VISIBLE ARM RESOURCES in this subscription.')
 else:
  print('FLAG\tRESOURCE GROUP\tTYPE\tNAME\tREGION')
  for r in sorted(resources,key=lambda r:(r.get('resourceGroup',''),r.get('type',''),r.get('name',''))):
   typ=r.get('type','');flag='REVIEW-COST' if any(x in typ.lower() for x in risk) else 'REVIEW'
   print('\t'.join([flag,r.get('resourceGroup','?'),typ,r.get('name','?'),r.get('location','?')]))
 print('Visible resources in target group: '+str(sum(r.get('resourceGroup','').lower()==rg.lower() for r in resources)))
print('\n=== Summary ===')
print('Visible ARM resources remaining: '+str(remaining))
print('Inventory status: '+('INCOMPLETE (some queries failed)' if unknown else 'completed for the subscriptions and permissions visible to this login'))
print('REVIEW-COST means potentially billable, not confirmed charges. REVIEW does not mean free.')
print('This is NOT a zero-bill certificate: restricted scopes, other tenants, soft-deleted backup data, reservations, savings plans, Marketplace/SaaS subscriptions and delayed usage charges require billing review.')
print('Check Azure Portal > Cost Management + Billing > Cost analysis, Reservations, Savings plans, and recurring purchases. Historical costs can appear after deletion.')
print('No resources were deleted or modified; default subscription was not changed.')
sys.exit(2 if unknown else 1 if remaining else 0)
PY
