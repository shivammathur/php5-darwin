#!/usr/bin/env python3
"""Select runtime and PECL build files from MacPorts manifests.

Filter the complete post-Imagick manifest with the original base manifest so
aliases added by later ports cannot reintroduce removed base build tools.
"""
import argparse
import json
import os
from pathlib import Path
import re

LEGAL = re.compile(r'(^|/)(copying[^/]*|copyright[^/]*|licen[sc]e[^/]*|notice[^/]*)$', re.I)
DOCUMENTATION = re.compile(r'(^|/)share/(doc|man|info|gtk-doc)(/|$)')
BUILD_TOOLS = {'mako-render', 'markdown_py', 'g-ir-annotation-tool',
               'g-ir-doc-tool', 'g-ir-scanner'}
PECL_TOOLS = {'pear', 'peardev', 'pecl', 'autoconf', 'autoheader', 'autom4te',
              'autoreconf', 'autoscan', 'autoupdate', 'ifnames', 'glibtool',
              'glibtoolize', 'libtoolize', 'pkg-config', 'gm4', 'gsed', 'daemondo'}


def keep(path, base):
    name = path.removeprefix('/opt/local/')
    if LEGAL.search(name):
        return True
    if DOCUMENTATION.search(name):
        return False
    if name.startswith(('Library/Frameworks/', 'lib/perl5/', 'lib/python',
                        'lib/texi2any/', 'share/texi2any/',
                        'include/python', 'lib/pkgconfig/python')):
        return False
    if name.startswith('libexec/boost/'):
        return name.endswith('.dylib') and 'libboost_python' not in name
    if name.startswith('bin/'):
        tool = name[4:]
        if tool in BUILD_TOOLS:
            return False
        if path in base:
            return not tool.startswith('python') and (
                tool.startswith('php') or tool in PECL_TOOLS or tool.endswith('-config'))
    if name.startswith('sbin/') and path in base:
        return name[5:].startswith('php-fpm')
    return True


def select(paths, base, root=Path('/')):
    selected = {path for path in paths if keep(path, base)}
    # Symlinks can name other symlinks or directories. Iterate until aliases
    # into removed trees are all gone, including those in the Imagick sidecar.
    changed = True
    while changed:
        changed = False
        for path in tuple(selected):
            file = root / path.lstrip('/')
            if not file.is_symlink():
                continue
            target = os.readlink(file)
            target = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not target.startswith('/opt/local/'):
                continue
            available = target in selected or any(p.startswith(target + '/') for p in selected)
            if not available:
                selected.remove(path)
                changed = True
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--base', type=Path, help='Unfiltered base manifest')
    parser.add_argument('--root', type=Path, default=Path('/'))
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    paths = set(args.manifest.read_text().splitlines())
    if any(not p.startswith('/opt/local/') for p in paths):
        raise SystemExit('Manifest contains a path outside /opt/local')
    base = set(args.base.read_text().splitlines()) if args.base else paths
    selected = select(paths, base, args.root)
    args.output.write_text(''.join(p + '\n' for p in sorted(selected)))
    sizes = {p: (args.root / p.lstrip('/')).lstat().st_size for p in paths}
    report = dict(original_files=len(paths), selected_files=len(selected),
                  original_bytes=sum(sizes.values()),
                  selected_bytes=sum(sizes[p] for p in selected),
                  removed=sorted(paths - selected))
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'removed'}))


if __name__ == '__main__':
    main()
