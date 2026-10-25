import tempfile,pathlib,subprocess,os
source=pathlib.Path('dualstack/vless-ipv6.sh').read_text()
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d);rt=p/'runtime';rt.mkdir()
 lists={'current_mode':'11','traffic_mode':'selective','ipv6_guard':'strict','proxy_devices':'mac:aa:00:00:00:00:01\nmac:aa:00:00:00:00:02\nmac:aa:00:00:00:00:03','udp_devices':'mac:aa:00:00:00:00:01\nmac:aa:00:00:00:00:03\nmac:aa:00:00:00:00:04','ipv6_devices':'mac:aa:00:00:00:00:01\nmac:aa:00:00:00:00:02\nmac:aa:00:00:00:00:04'}
 for k,v in lists.items():(rt/k).write_text(v+'\n')
 (p/'helper.sh').write_text(source.replace('BASE=/data/proxy-mode','BASE='+d))
 mocks={'ip6tables':'echo "ip6tables $*" >> "$TRACE"\ncase " $* " in *" -C "*) exit 1;; esac\nif [ -n "$FAIL_REDIRECT" ]; then case " $* " in *" --to-ports "*) exit 2;; esac; fi\nexit 0', 'ip':'echo "ip $*" >> "$TRACE"\ncase "$*" in "-6 rule del "*) exit 1;; "-6 addr show dev "*) echo " inet6 fd75:60:0:168::1/126 scope global";; "-6 addr show") echo " inet6 2408::1/64 scope global";; esac\nexit 0','jsonfilter':'case "$*" in *"inbounds"*) echo vless6-redirect-in;; *) echo vless;; esac'}
 for name,body in mocks.items():f=p/name;f.write_text('#!/bin/sh\n'+body+'\n');f.chmod(0o755)
 env=dict(os.environ,PATH=d+':'+os.environ['PATH'],TRACE=str(p/'trace'),FAIL_REDIRECT='')
 subprocess.run(['sh',str(p/'helper.sh'),'apply'],env=env,check=True)
 t=(p/'trace').read_text()
 assert 'addrtype' not in t
 assert '--mac-source aa:00:00:00:00:01 -p udp -j MARK' in t
 assert '--mac-source aa:00:00:00:00:02 -p tcp -j REDIRECT' in t
 assert '--mac-source aa:00:00:00:00:02 -p udp' not in t
 assert 'aa:00:00:00:00:03' not in t and 'aa:00:00:00:00:04' not in t
 assert '-i br-lan -o u60udp0 -p udp -m mark --mark 0x68/0xff -j ACCEPT' in t
 assert '-o rmnet_data0' not in t
 assert t.index('route replace blackhole') < t.index('rule add fwmark') < t.index('-t mangle -I PREROUTING')
 assert (rt/'vless_ipv6_applied').read_text().strip()=='on'
 env['FAIL_REDIRECT']='yes';(p/'trace').write_text('')
 assert subprocess.run(['sh',str(p/'helper.sh'),'apply'],env=env).returncode!=0
 t=(p/'trace').read_text();assert t.count('-X U60PM_VLESS6_TCP')>=2
 assert (rt/'vless_ipv6_applied').read_text().strip()=='off'
 env['FAIL_REDIRECT']='';(rt/'current_mode').write_text('5\n');(p/'trace').write_text('')
 subprocess.run(['sh',str(p/'helper.sh'),'apply'],env=env,check=True)
 assert 'REDIRECT --to-ports' not in (p/'trace').read_text()
 print('PASS: TCP/UDP/Guard selector intersections, IPv6 blackhole order, no cellular bypass, failure cleanup, SSH isolation')
