"""Use the authenticated source in every bundled PHP subport, never public PHP archives."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ports=Path(os.environ['PORTS_ROOT']); reports=Path(os.environ['REPORT_DIR'])
minor=os.environ['PHP_VERSION'];short=minor.replace('.','');source=Path(os.environ['SOURCE_ARCHIVE'])
assert hashlib.sha256(source.read_bytes()).hexdigest()==os.environ['SOURCE_SHA256']
source_dir=Path(os.environ['PRIVATE_TASK_DIR'])/'source';source_dir.mkdir()
with tarfile.open(source) as t:
    t.extractall(source_dir,filter='data')
root=source_dir/os.environ['SOURCE_ROOT']
before={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
autoconf='213' if minor=='5.3' else '269'
env={**os.environ,'PHP_AUTOCONF':'/opt/local/bin/autoconf'+autoconf,'PHP_AUTOHEADER':'/opt/local/bin/autoheader'+autoconf}
subprocess.run(['bash','buildconf','--force'],cwd=root,env=env,check=True)
assert (root/'configure').is_file()
# The private inputs are Git exports; MacPorts' ordinary release archives have
# these generated parsers already. Generate only missing files with pinned Bison.
parsers=[]
for stem,prefix in [('zend_language_parser','zend'),('zend_ini_parser','ini_')]:
    for suffix in ('.c','.h'):
        assert not (root/'Zend'/(stem+suffix)).exists(), 'Unexpected pre-generated parser'
    subprocess.run([os.environ['PRIVATE_BISON'],'-y','-p',prefix,'-v','-d',stem+'.y','-o',stem+'.c'],cwd=root/'Zend',check=True)
    for suffix in ('.c','.h'):
        file=root/'Zend'/(stem+suffix)
        parsers.append({'path':str(file.relative_to(root)),'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
for name,sha in before.items():
    assert (root/name).is_file() and hashlib.sha256((root/name).read_bytes()).hexdigest()==sha, 'Bootstrap changed original source: '+name
extension='bz2' if minor in ('5.3','5.4') else 'xz'
name=f"php-{os.environ['PHP_FULL_VERSION']}-private-{os.environ['SOURCE_SHA256'][:16]}.tar.{extension}"
archive=source_dir/name
# Preserve MacPorts' eagerly computed extension build paths. Only the derived
# archive root is normalized; the authenticated original archive is unchanged.
prepared_root='php-'+os.environ['PHP_FULL_VERSION']
with tarfile.open(archive,'w:'+extension) as t:t.add(root,arcname=prepared_root)
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
subdir='private-php'+short+'-'+os.environ['SOURCE_SHA256'][:16]
dist=Path('/opt/local/var/macports/distfiles')/subdir
dist.mkdir(parents=True,exist_ok=True);shutil.copyfile(archive,dist/name)
os.chmod(dist,0o755);os.chmod(dist/name,0o644)
# Rebase only FPM configuration context: the private archive contains an extra
# process-priority comment block. Preserve every upstream requested setting.
fpm=root/'sapi/fpm/php-fpm.conf.in';old=fpm.read_text();new=old
for a,b in [(';pid = run/php-fpm.pid',';pid = run/@PHP@/php-fpm.pid'),
            (';error_log = log/php-fpm.log','error_log = log/@PHP@/php-fpm.log'),
            (';syslog.ident = php-fpm','syslog.ident = @PHP@-fpm'),
            ('; Send FPM to background. Set to \'no\' to keep FPM in foreground for debugging.',
             '; Send FPM to background. Set to \'no\' to keep FPM in foreground for debugging\n; or for use with launchd.'),
            (';daemonize = yes','daemonize = no')]:
    assert new.count(a)==1,(minor,a)
    new=new.replace(a,b)
fpm_patch=ports/'lang/php/files'/f'patch-php{short}-sapi-fpm-php-fpm.conf.in.diff'
if fpm_patch.is_symlink():fpm_patch.unlink()
fpm_patch.write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),
    fromfile='a/sapi/fpm/php-fpm.conf.in',tofile='b/sapi/fpm/php-fpm.conf.in')))
# The override is evaluated after every upstream branch/subport declaration.
guard=ports/'lang/php/private-mitigation.patch'
shutil.copyfile(os.environ['MITIGATION_PATCH'],guard)
# MacPorts normally extracts just an extension subtree. Keep the full exact
# source here so the per-port mitigation check can cover every original hunk.
p=ports/'lang/php/Portfile'
s=p.read_text()
for selector in ('${worksrcdir}/ext/${extension}', '${worksrcdir}/ext/pdo', '${worksrcdir}/ext/spl'):
    line='extract.post_args-append '+selector
    assert s.count(line)==1
    s=s.replace(line, 'if {${subport_branch} ne "'+minor+'"} { '+line+' }')
p.write_text(s)
# ICU 68 changes FALSE to false before ICU 71 applies. Rebase that context
# line only; preserve all added and removed lines of the upstream patch.
icu=ports/'lang/php/files/patch-php55-ext-intl-icu-71.diff'
text=icu.read_text();old_context=' \t\treturn FALSE;'
assert text.count(old_context)==1
if icu.is_symlink():icu.unlink()
icu.write_text(text.replace(old_context,' \t\treturn false;'))
with p.open('a') as f:
    f.write(f'''\n# Private staging: exact authenticated source; no public package substitution.
if {{${{subport_branch}} eq "{minor}"}} {{
    revision 999999
    master_sites {{}}
    dist_subdir {subdir}
    distfiles {name}
    worksrcdir {prepared_root}
    checksums sha256 {sha} size {archive.stat().st_size}
    patch.pre_args-append --fuzz=0
    post-patch {{
        # Verify every mitigation hunk remains present after platform patches.
        system -W ${{worksrcpath}} "/usr/bin/patch --force --fuzz=0 --dry-run -R -p1 -i {guard}"
    }}
}}
''')
proof={'original_sha256':os.environ['SOURCE_SHA256'],'root':root.name,'original_files':len(before),'original_files_unchanged':True,
       'autoconf':autoconf,'bison':'2.6.4','generated_parsers':parsers,'prepared_source':{'name':name,'root':prepared_root,'sha256':sha,'bytes':archive.stat().st_size},
       'fpm_patch_sha256':hashlib.sha256(fpm_patch.read_bytes()).hexdigest(), 'portfile_sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(reports/'source-bootstrap.json').write_text(json.dumps(proof,indent=2))
shutil.copyfile(fpm_patch,reports/'fpm-context.patch')
# Force every PHP port to compile; install its non-PHP dependencies from the
# ordinary MacPorts archives first. The PHP core dependency is already pinned.
p=Path(os.environ['BUILD_REPOSITORY'])/'scripts/build-native-cache.sh';s=p.read_text()
s=s.replace('  sudo "$port" -N install --allow-failing "$@"','''  local target=$1
  if [[ "$target" = "$php_version" || "$target" = "$php_version-"* ]]; then
    local dependency
    for dependency in "$@"; do
      [[ "$dependency" = "$php_version" || "$dependency" = "$php_version-"* ]] || continue
      sudo "$port" -N install --allow-failing "depof:$dependency"
    done
    sudo "$port" -N -s install --allow-failing "$@"
  else
    sudo "$port" -N install --allow-failing "$@"
  fi''')
# Route the existing explicit source-build extension calls through the same
# dependency-first function; source compilation remains mandatory.
s=s.replace('install_command=(sudo "$port" -N -s install --allow-failing)','install_command=(install_ports)')
p.write_text(s)
