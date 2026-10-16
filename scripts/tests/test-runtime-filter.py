#!/usr/bin/env python3
"""Exercise pruning across the base/Imagick boundary and preserve PECL data."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('runtime', Path(__file__).parents[1] / 'filter-runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeFilterTest(unittest.TestCase):
    def test_base_and_sidecar(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            base = {
                'bin/php55', 'bin/autoconf', 'bin/autom4te', 'bin/perl5.34',
                'lib/perl5/5.34/core.pm', 'lib/texi2any/parser.so',
                'Library/Frameworks/Python.framework/Versions/3.13/Python',
                'include/php55/main/php.h', 'lib/libc-client4.a',
                'lib/libssl.dylib', 'share/autoconf/autoconf.m4',
                'share/doc/openssl/LICENSE', 'share/doc/openssl/manual.html',
                'libexec/boost/include/boost/test.hpp',
                'libexec/boost/lib/libboost_system.dylib',
                'libexec/boost/lib/libboost_python313.dylib',
            }
            extra = {'bin/gs', 'bin/g-ir-scanner', 'bin/convert',
                     'share/ghostscript/Resource/Init/gs_init.ps',
                     'etc/ImageMagick-7/delegates.xml', 'share/doc/ghostscript/COPYING'}
            aliases = {'bin/perl': 'perl5.34', 'bin/sidecar-perl': 'perl',
                       'bin/php': 'php55', 'lib/boost': 'libexec-removed',
                       'bin/system-perl': '/usr/bin/perl'}
            for name in base | extra:
                file = root / 'opt/local' / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('fixture')
            for name, target in aliases.items():
                (root / 'opt/local' / name).symlink_to(target)
            paths = {'/opt/local/' + p for p in base | extra | aliases.keys()}
            selected = runtime.select(paths, {'/opt/local/' + p for p in base}, root)
            for name in ('bin/php55', 'bin/php', 'bin/autoconf', 'bin/autom4te',
                         'include/php55/main/php.h', 'lib/libc-client4.a',
                         'share/autoconf/autoconf.m4', 'share/doc/openssl/LICENSE',
                         'bin/gs', 'bin/convert', 'share/doc/ghostscript/COPYING',
                         'etc/ImageMagick-7/delegates.xml', 'bin/system-perl'):
                self.assertIn('/opt/local/' + name, selected)
            for name in ('bin/perl5.34', 'bin/perl', 'bin/sidecar-perl',
                         'lib/perl5/5.34/core.pm', 'bin/g-ir-scanner',
                         'share/doc/openssl/manual.html', 'lib/texi2any/parser.so',
                         'libexec/boost/include/boost/test.hpp',
                         'libexec/boost/lib/libboost_python313.dylib', 'lib/boost'):
                self.assertNotIn('/opt/local/' + name, selected)


if __name__ == '__main__':
    unittest.main()
