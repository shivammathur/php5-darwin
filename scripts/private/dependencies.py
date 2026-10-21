import hashlib,json,subprocess,sys
from pathlib import Path
config=json.loads((Path(__file__).parent/'project.json').read_text())['dependencies']
kind,name,dest=sys.argv[1:]
if kind=='macports-package':
    expected=config['macports_packages'][name]
    url='https://github.com/macports/macports-base/releases/download/v2.12.6/'+name
elif kind=='bison':
    expected=config['bison_sha256']
    url='https://ftp.gnu.org/gnu/bison/bison-'+config['bison_version']+'.tar.gz'
else:
    assert kind=='ports-tree'
    expected=config['macports_ports_sha256']
    url='https://github.com/macports/macports-ports/archive/'+config['macports_ports_commit']+'.tar.gz'
subprocess.run(['/usr/bin/curl','-fsSL','--retry','3','--proto','=https',url,'-o',dest],check=True)
assert hashlib.sha256(Path(dest).read_bytes()).hexdigest()==expected,'Dependency digest mismatch'
