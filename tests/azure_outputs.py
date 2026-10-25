import tempfile,pathlib,json,base64,subprocess,os
root=pathlib.Path(__file__).resolve().parents[1]/'azure'
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d)
 params={'port':443,'sni':'www.example.com','uuid':'11111111-1111-4111-8111-111111111111','public_key':'test','short_id':'51','proxy_ipv6':True}
 (p/'result.json').write_text(json.dumps({'value':[{'message':'U60_VLESS_EXPORT='+base64.b64encode(json.dumps(params).encode()).decode()}]}))
 subprocess.run(['bash','-c','source "$1"; export_client "$2" 192.0.2.1 "$3"','test',str(root/'azure-vps-vless.sh'),str(p/'result.json'),str(p/'out')],env={**os.environ,'AZ_VPS_TEST_SOURCE_ONLY':'1'},check=True,stdout=subprocess.DEVNULL)
 c=json.loads((p/'out/mode11.json').read_text());assert c['dns']['strategy']=='ipv4_only';assert c['route']['final']=='mode11-vless';assert c['dns']['servers'][0]['detour']=='mode11-vless';assert not (p/'out/mode15.json').exists()
 (p/'az').write_text('''#!/usr/bin/env python3
import sys,json,os
s=' '.join(sys.argv[1:])
assert not any(x in sys.argv for x in ('delete','create','set','update'))
if s.startswith('account list'):print(json.dumps([{'name':'Test','id':'test','state':'Enabled'}]))
elif s.startswith('group list'):print('[]')
elif s.startswith('resource list'):
 if os.environ.get('CASE')=='failure':sys.stderr.write('AuthorizationFailed');sys.exit(1)
 print('[]' if os.environ.get('CASE')=='empty' else '[{"name":"orphan-disk","type":"Microsoft.Compute/disks","resourceGroup":"other"}]')
else:sys.exit(9)
''');(p/'az').chmod(0o755)
 for case,code in [('empty',0),('remaining',1),('failure',2)]:
  r=subprocess.run(['bash',str(root/'azure-paid-resources-check.sh')],env={**os.environ,'PATH':str(p)+':'+os.environ['PATH'],'CASE':case},capture_output=True,text=True)
  assert r.returncode==code,(case,r.stdout,r.stderr)
  if case=='remaining':assert 'orphan-disk' in r.stdout
  if case=='failure':assert 'INCOMPLETE' in r.stdout
print('PASS: Mode11-only / IPv4-only / matching tags / retained IPv6 fields; checker empty, orphan resource, denied query, no mutations')
