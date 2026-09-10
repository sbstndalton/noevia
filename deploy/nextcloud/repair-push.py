#!/usr/bin/env python3
"""Repair AIO push callbacks without trusting an Internet client address.
Run on the Docker host. Dry-run by default. Does not log configuration/secrets.
"""
import argparse, copy, http.client, json, os, re, socket, subprocess, time
from pathlib import Path

NAME = 'nextcloud-aio-notify-push'
NC = 'nextcloud-aio-nextcloud'
INTERNAL = 'http://nextcloud-aio-apache.nextcloud-aio:23973'
DOMAIN = 'nextcloud-aio-apache.nextcloud-aio'

class DockerConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        self.sock.settimeout(60);self.sock.connect('/var/run/docker.sock')

def docker(method, path, body=None):
    c=DockerConnection('localhost');raw=None if body is None else json.dumps(body)
    c.request(method,path,body=raw,headers={'Content-Type':'application/json'})
    r=c.getresponse();data=r.read();c.close()
    if r.status>=400:raise RuntimeError(f'Docker {method} {path.split("?")[0]} failed ({r.status})')
    return json.loads(data) if data else None

def replacement(info):
    config=copy.deepcopy(info['Config'])
    config['Env']=[v for v in config.get('Env',[]) if not v.startswith('NEXTCLOUD_URL=')]+['NEXTCLOUD_URL='+INTERNAL]
    # Pin exactly the image already running; do not pull an unrelated update.
    config['Image']=info['Image']
    config['HostConfig']=copy.deepcopy(info['HostConfig'])
    config['NetworkingConfig']={'EndpointsConfig':{name:{'Aliases':[a for a in settings.get('Aliases',[]) or [] if not re.fullmatch('[a-f0-9]{12,64}',a)]} for name,settings in info['NetworkSettings']['Networks'].items()}}
    return config

def occ(*args):
    return subprocess.check_output(['docker','exec','--user','www-data',NC,'php','occ',*args],text=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    info=docker('GET','/containers/'+NAME+'/json')
    domains=occ('config:system:get','trusted_domains').splitlines()
    configured=('NEXTCLOUD_URL='+INTERNAL) in info['Config'].get('Env',[])
    if configured and DOMAIN in domains:
        print('Internal push callback already configured.');print(occ('notify_push:self-test'));return
    print('Change: notify-push callback -> internal AIO HTTP route; public HTTPS endpoint unchanged.')
    print('Change: add only the internal Apache hostname to trusted_domains if missing; trusted_proxies unchanged.')
    if not args.apply:return
    backup=Path('/mnt/docker/appdata/cowork/backups')/('notify-push-'+time.strftime('%Y%m%d-%H%M%S'))
    backup.mkdir(parents=True,mode=0o700)
    for name,value in [('container.json',info),('domains.json',domains)]:
        fd=os.open(backup/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as f:json.dump(value,f)
    # Read exact indices rather than assuming there are no gaps in the array.
    domain_index=None
    if DOMAIN not in domains:
        for i in range(100):
            try:occ('config:system:get','trusted_domains',str(i))
            except subprocess.CalledProcessError:domain_index=i;break
        if domain_index is None:raise RuntimeError('No free trusted-domain slot')
        occ('config:system:set','trusted_domains',str(domain_index),'--value='+DOMAIN)
    old=NAME+'-rollback-'+str(int(time.time()));created=False;renamed=False
    try:
        docker('POST','/containers/'+NAME+'/stop?t=20')
        docker('POST','/containers/'+NAME+'/rename?name='+old);renamed=True
        docker('POST','/containers/create?name='+NAME,replacement(info));created=True
        docker('POST','/containers/'+NAME+'/start')
        # Allow normal startup, but never accept a broken self-test.
        for attempt in range(12):
            time.sleep(2)
            try:
                result=occ('notify_push:self-test');break
            except subprocess.CalledProcessError:
                if attempt==11:raise RuntimeError('Push self-test did not pass')
        print(result);print('Repair verified. Rollback container: '+old);print('Private backup: '+str(backup))
    except Exception:
        if created:docker('DELETE','/containers/'+NAME+'?force=true')
        if renamed:docker('POST','/containers/'+old+'/rename?name='+NAME)
        docker('POST','/containers/'+NAME+'/start')
        if domain_index is not None:occ('config:system:delete','trusted_domains',str(domain_index))
        raise

if __name__=='__main__':main()
