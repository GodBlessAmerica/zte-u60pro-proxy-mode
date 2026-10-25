import pathlib,tempfile,subprocess,os,json,re
src=pathlib.Path('dualstack')
config=json.dumps({'dns':{'strategy':'prefer_ipv6'},'inbounds':[{'tag':'vless6-redirect-in'},{'tag':'udp-tun-in','address':['fd75:60:0:168::1/126']}],'outbounds':[{'type':'vless'}]})
for failure in (False,True):
 with tempfile.TemporaryDirectory() as d:
  p=pathlib.Path(d);data=p/'data';base=data/'proxy-mode';scripts=base/'scripts';scripts.mkdir(parents=True);rt=base/'runtime';rt.mkdir();cfg=base/'configs';cfg.mkdir();b=base/'bin';b.mkdir();ctl=data/'u60proxy/bin';ctl.mkdir(parents=True);state=data/'u60proxy/state';state.mkdir();pkg=p/'package';pkg.mkdir();tools=p/'tools';tools.mkdir()
  for f in src.glob('*.sh'):
   text=re.sub(r'(?<!files)/data/',str(data)+'/',f.read_text())
   text=text.replace('\"$B/files$p\"','\"$B/files${p#'+str(p)+'}\"')
   text=text.replace('$(dirname \"$p\")','$(dirname \"${p#'+str(p)+'}\")')
   (pkg/f.name).write_text(text)
  (p/'new.json').write_text(config)
  old='{"inbounds":[],"outbounds":[{"type":"ssh"}],"route":{"final":"ssh"}}\n'
  (cfg/'mode11.json').write_text(old);(cfg/'mode5.json').write_text(old)
  for k,v in {'current_mode':'5','traffic_mode':'selective','ipv6_guard':'strict','proxy_devices':'mac:aa:00:00:00:00:01','udp_devices':'mac:aa:00:00:00:00:01','ipv6_devices':'mac:aa:00:00:00:00:01'}.items():(rt/k).write_text(v+'\n')
  (state/'current_mode').write_text('5\n')
  def exe(path,text):path.write_text('#!/bin/sh\n'+text+'\n');path.chmod(0o755)
  original='#!/bin/sh\nexit 0\n';(scripts/'traffic.sh').write_text(original);(scripts/'traffic.sh').chmod(0o755)
  exe(b/'sing-box','exit 0')
  exe(ctl/'u60proxy',f'''if [ "$3" = 11 ] && [ "$FAIL_MODE11" = yes ]; then exit 1; fi
cp "{cfg}/mode$3.json" "{rt}/active.json"
echo "$3" > "{rt}/current_mode"
echo "$3" > "{state}/current_mode"
"{scripts}/traffic.sh" apply''')
  exe(tools/'ip','case "$*" in "-6 rule del "*) exit 1;; "-6 addr show dev "*) echo " inet6 fd75:60:0:168::1/126 scope global";; "-6 addr show") echo " inet6 2408::1/64 scope global";; esac\nexit 0')
  exe(tools/'ip6tables','case " $* " in *" -C "*) exit 1;; esac\nexit 0')
  jf=tools/'jsonfilter';jf.write_text('''#!/usr/bin/env python3
import json,sys
c=json.load(open(sys.argv[sys.argv.index('-i')+1]));e=sys.argv[sys.argv.index('-e')+1]
if e=='@.outbounds[0].type':print(c['outbounds'][0]['type'])
elif e=='@.inbounds[*].tag':
 for i in c['inbounds']:print(i['tag'])
elif e=='@.inbounds[*].address[*]':
 for i in c['inbounds']:
  for a in i.get('address',[]):print(a)
elif e=='@.dns.strategy':print(c['dns']['strategy'])
else:raise SystemExit(e)
''');jf.chmod(0o755)
  env=dict(os.environ,PATH=str(tools)+':'+os.environ['PATH'],FAIL_MODE11='yes' if failure else 'no')
  r=subprocess.run(['sh',str(pkg/'install.sh'),str(p/'new.json')],env=env,capture_output=True,text=True)
  if failure:
   assert r.returncode!=0,(r.stdout,r.stderr)
   assert (scripts/'traffic.sh').read_text()==original
   assert (cfg/'mode11.json').read_text()==old
   assert not(scripts/'vless-ipv6.sh').exists()
   assert (rt/'current_mode').read_text().strip()=='5'
  else:
   assert r.returncode==0,(r.stdout,r.stderr)
   assert (rt/'vless_ipv6_applied').read_text().strip()=='on'
   subprocess.run(['sh',str(pkg/'rollback.sh')],env=env,check=True,stdout=subprocess.DEVNULL)
   assert (scripts/'traffic.sh').read_text()==original
   assert (cfg/'mode11.json').read_text()==old
   assert not(scripts/'vless-ipv6.sh').exists()
 print('PASS: '+('failed activation automatically restores previous scripts/config/mode' if failure else 'install activates IPv6 adapter; explicit rollback restores prior state'))
