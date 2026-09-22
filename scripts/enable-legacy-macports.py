#!/usr/bin/env python3

import re
import sys
from pathlib import Path


def replace_xcode_guard(path: Path, branch_expression: str) -> None:
    source = path.read_text()
    pattern = re.compile(
        r"^    platform darwin \{\n"
        rf"        if \{{\[vercmp \$\{{{re.escape(branch_expression)}\}} < 7\.0\] && "
        r"\[vercmp \$\{xcodeversion\} >= 12\.0\]\} \{\n"
        r".*?"
        r"^        \}\n"
        r"^    \}\n",
        re.MULTILINE | re.DOTALL,
    )
    replacement = (
        "    platform darwin {\n"
        f"        if {{[vercmp ${{{branch_expression}}} < 7.0] && "
        "[vercmp ${xcodeversion} >= 12.0]} {\n"
        "            # Downgrade diagnostics that modern Clang promotes to "
        "errors for legacy C.\n"
        "            # Keep Autoconf 2.73 from selecting incompatible C23 semantics.\n"
        "            configure.cflags-append \\\n"
        "                -std=gnu99 \\\n"
        "                -Wno-error=implicit-function-declaration \\\n"
        "                -Wno-error=implicit-int \\\n"
        "                -Wno-error=incompatible-function-pointer-types \\\n"
        "                -Wno-error=int-conversion\n"
        "            configure.cxxflags-append -Wno-register\n"
        "        }\n"
        "    }\n"
    )
    if branch_expression == "branch":
        replacement += (
            "\n"
            "    if {[vercmp ${branch} < 7.0]} {\n"
            "        post-patch {\n"
            "            # libxml2 2.15 removed ATTRIBUTE_UNUSED from its "
            "public headers.\n"
            "            reinplace {s|int compression ATTRIBUTE_UNUSED)|int "
            "compression)|} \\\n"
            "                ${worksrcpath}/ext/libxml/libxml.c\n"
            "        }\n"
            "    }\n"
        )
    if replacement in source:
        return
    match = pattern.search(source)
    if match is None or 'return -code error "incompatible Xcode version"' not in match.group():
        raise RuntimeError(f"MacPorts PHP Xcode guard changed in {path}")
    source = source[: match.start()] + replacement + source[match.end() :]
    path.write_text(source)


def fix_pcntl_patch_guard(path: Path) -> None:
    source = path.read_text()
    old_guard = (
        "    if {[vercmp ${branch} <= 8.0]} {\n"
        "        patchfiles-append   patch-${php}-ext-pcntl-pcntl.c.diff\n"
        "    }\n"
    )
    new_guard = (
        "    if {[vercmp ${branch} >= 7.4] && [vercmp ${branch} <= 8.0]} {\n"
        "        patchfiles-append   patch-${php}-ext-pcntl-pcntl.c.diff\n"
        "    }\n"
    )
    if new_guard in source:
        return
    if source.count(old_guard) != 1:
        raise RuntimeError(f"MacPorts PHP pcntl patch guard changed in {path}")
    path.write_text(source.replace(old_guard, new_guard))


def fix_zip_version_guard(path: Path) -> None:
    source = path.read_text()
    old_guard = "if {[vercmp ${php.branch} >= 5.4]} {\n"
    new_guard = "if {[vercmp ${php.branch} >= 5.6]} {\n"
    if new_guard in source:
        return
    if source.count(old_guard) != 1:
        raise RuntimeError(f"MacPorts PHP Zip version guard changed in {path}")
    path.write_text(source.replace(old_guard, new_guard))


def isolate_legacy_openssl(path: Path) -> None:
    source = path.read_text()
    old_block = (
        "    depends_lib-append      port:kerberos5 \\\n"
        "                            port:libcomerr\n"
        "\n"
        "    post-extract {\n"
        "        move ${php.build_dirs}/config0.m4 ${php.build_dirs}/config.m4\n"
        "    }\n"
        "\n"
        "    configure.args-append   --with-kerberos=${prefix}\n"
    )
    new_block = (
        "    if {[vercmp ${branch} < 5.4]} {\n"
        "        # Avoid loading OpenSSL 1.0 and OpenSSL 3 through Kerberos in\n"
        "        # the same legacy PHP process.\n"
        "        configure.args-append   --without-kerberos\n"
        "    } else {\n"
        "        depends_lib-append      port:kerberos5 \\\n"
        "                                port:libcomerr\n"
        "        configure.args-append   --with-kerberos=${prefix}\n"
        "    }\n"
        "\n"
        "    post-extract {\n"
        "        move ${php.build_dirs}/config0.m4 ${php.build_dirs}/config.m4\n"
        "    }\n"
    )
    if new_block not in source:
        if source.count(old_block) != 1:
            raise RuntimeError(f"MacPorts PHP OpenSSL configuration changed in {path}")
        source = source.replace(old_block, new_block)

    old_linkage = "        configure.args-append   --with-openssl=shared\n"
    new_linkage = (
        "        # Record the exact OpenSSL 1.0 dylibs instead of relying on\n"
        "        # flat-namespace symbols supplied by another extension.\n"
        "        configure.args-append   --with-openssl=shared,[openssl::install_area]\n"
    )
    if new_linkage not in source:
        if source.count(old_linkage) != 1:
            raise RuntimeError(f"MacPorts PHP OpenSSL linkage changed in {path}")
        source = source.replace(old_linkage, new_linkage)

    path.write_text(source)


def fix_arm64_openssl_optimization(path: Path) -> None:
    # Clang 14+ miscompiles OpenSSL 1.0.2's generic EC arithmetic at -O2/-O3
    # on ARM. Keep the native target but use the verified -O1 workaround.
    # https://github.com/rbenv/homebrew-tap/commit/030470c2379425ee8f08f1979bbbe4eb37e993a0
    source = path.read_text()
    old = '"darwin64-arm64-cc","cc:-arch arm64 -O3 '
    new = '"darwin64-arm64-cc","cc:-arch arm64 -O1 '
    if new in source:
        return
    if source.count(old) != 1:
        raise RuntimeError(f"MacPorts OpenSSL ARM target changed in {path}")
    path.write_text(source.replace(old, new))


def fix_legacy_extension_sources(ports_root: Path) -> None:
    patches = {
        "php-amf": (
            "5.3 5.4 5.5",
            "        # PHP 5.3+ removed the old ZVAL_* refcount aliases.\n"
            "        reinplace {s|ZVAL_ADDREF|Z_ADDREF_P|g; "
            "s|ZVAL_DELREF|Z_DELREF_P|g; s|ZVAL_REFCOUNT|Z_REFCOUNT_P|g} "
            "${worksrcpath}/amf.c\n"
            "        # Zend writes a full ulong hash key: int buffers corrupt the\n"
            "        # stack on 64-bit builds. Keep signed keys and printf in sync.\n"
            "        reinplace {s|int keyIndex;|long keyIndex;|g; "
            "s|ulong keyIndex;|long keyIndex;|g; "
            "s|int key_index;|ulong key_index;|g; "
            "s|\"%d\",keyIndex|\"%ld\",keyIndex|g; "
            "s|char txt\\[20\\]|char txt[32]|g; "
            "s|int iIndex;|long iIndex;|g; "
            "s|array item %d|array item %ld|g; "
            "s|array index %d|array index %ld|g} ${worksrcpath}/amf.c\n"
            "        # AMF3 associative arrays need the newly initialized table.\n"
            "        reinplace {/HashTable \\* htOutput = HASH_OF(\\*rval);/ {"
            "s|HashTable \\* htOutput = HASH_OF(\\*rval);|"
            "HashTable * htOutput;|; "
            "n; "
            "s|amf_array_init(\\*rval, maxIndex TSRMLS_CC);|"
            "amf_array_init(*rval, maxIndex TSRMLS_CC); htOutput = HASH_OF(*rval);|;}} "
            "${worksrcpath}/amf.c\n"
        ),
        "php-amqp": (
            "5.3 5.4 5.5",
            "        # strtoimax returns intmax_t, not an implicitly declared int.\n"
            "        reinplace {s|#include <stdint.h>|#include <stdint.h>\\n"
            "#include <inttypes.h>|} ${worksrcpath}/amqp_type.c\n"
            "        if {${php.branch} eq \"5.3\"} {\n"
            "            reinplace {s|_php_math_number_format_ex|_php_math_number_format|g; "
            "s|timestamp, 0, \"\", 0, \"\", 0|timestamp, 0, 0, 0|g} "
            "${worksrcpath}/amqp_timestamp.c\n"
            "        }\n"
        ),
        "php-dbase": (
            "5.3 5.4 5.5",
            "        # Backport PHP bug #74983: the disk field has only 11 bytes.\n"
            "        reinplace {s|dbf->db_fname, DBF_NAMELEN + 1|"
            "dbf->db_fname, DBF_NAMELEN|} ${worksrcpath}/dbf_head.c\n"
            "        if {${php.branch} eq \"5.3\"} {\n"
            "            # PHP 5.3 has the char-based number formatting API.\n"
            "            reinplace {s|_php_math_number_format_ex|_php_math_number_format|g; "
            "s|\"\\.\", 1, \"\", 0|'.', 0|g} ${worksrcpath}/dbase.c\n"
            "        }\n"
        ),
    }
    for port, (branches, patch) in patches.items():
        path = ports_root / "php" / port / "Portfile"
        source = path.read_text()
        block = (
            "\nif {${php.branch} in {" + branches + "}} {\n"
            "    post-patch {\n" + patch + "    }\n}\n"
        )
        if block not in source:
            path.write_text(source + block)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <MacPorts ports tree>")

    ports_root = Path(sys.argv[1]).resolve()
    php_portfile = ports_root / "lang/php/Portfile"
    replace_xcode_guard(php_portfile, "branch")
    fix_pcntl_patch_guard(php_portfile)
    isolate_legacy_openssl(php_portfile)
    replace_xcode_guard(
        ports_root / "_resources/port1.0/group/php-1.1.tcl", "php.branch"
    )
    fix_zip_version_guard(ports_root / "php/php-zip/Portfile")
    fix_arm64_openssl_optimization(
        ports_root / "devel/openssl10/files/darwin64-arm64-cc.patch"
    )
    fix_legacy_extension_sources(ports_root)


if __name__ == "__main__":
    main()
