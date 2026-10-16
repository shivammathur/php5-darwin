#!/usr/bin/env python3
"""Check packaged aliases and executable script interpreters after isolation."""
import os
from pathlib import Path
import sys

prefix = Path(sys.argv[1] if len(sys.argv) > 1 else '/opt/local')
errors = []
for directory, directories, files in os.walk(prefix):
    for name in directories + files:
        path = Path(directory) / name
        if path.is_symlink():
            if not path.exists():
                errors.append('Broken symlink: %s -> %s' % (path, os.readlink(path)))
            continue
        if not path.is_file() or not os.access(path, os.X_OK):
            continue
        with path.open('rb') as file:
            header = file.read(256)
        if header.startswith(b'#!'):
            interpreter = header.splitlines()[0][2:].strip().split()[0].decode()
            if interpreter.startswith('/') and not Path(interpreter).is_file():
                errors.append('Missing interpreter: %s -> %s' % (path, interpreter))
if errors:
    raise SystemExit('\n'.join(errors))
print('Runtime symlinks and executable script interpreters are present')
