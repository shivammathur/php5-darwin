#!/usr/bin/env bash

set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d)
prefix="$fixture/prefix"
mkdir -p "$prefix/bin" "$prefix/lib" "$fixture/reports"

audit() {
  AUDIT_DIR="$fixture/reports/$1" bash "$repo/scripts/audit-dependencies.sh" "$prefix" "$2"
}

if audit empty arm64; then
  echo 'Empty cache incorrectly passed the audit' >&2
  exit 1
fi

clang -arch arm64 -dynamiclib -x c /dev/null -o "$prefix/lib/native.dylib" \
  -install_name "$prefix/lib/native.dylib"
audit native arm64

clang -arch x86_64 -dynamiclib -x c /dev/null -o "$prefix/lib/wrong.dylib" \
  -install_name "$prefix/lib/wrong.dylib"
if audit wrong arm64; then
  echo 'Wrong architecture incorrectly passed the audit' >&2
  exit 1
fi
mv "$prefix/lib/wrong.dylib" "$fixture/wrong.dylib"

clang -arch arm64 -dynamiclib -x c /dev/null -o "$prefix/lib/missing.dylib" \
  -install_name "$prefix/lib/nonexistent.dylib"
if audit missing arm64; then
  echo 'Missing dependency incorrectly passed the audit' >&2
  exit 1
fi
mv "$prefix/lib/missing.dylib" "$fixture/missing.dylib"

clang -arch arm64 -dynamiclib -x c /dev/null -o "$prefix/lib/external.dylib" \
  -install_name /opt/homebrew/lib/not-bundled.dylib
if audit external arm64; then
  echo 'External dependency incorrectly passed the audit' >&2
  exit 1
fi
mv "$prefix/lib/external.dylib" "$fixture/external.dylib"

lipo -create "$prefix/lib/native.dylib" "$fixture/wrong.dylib" \
  -output "$prefix/lib/universal.dylib"
install_name_tool -id "$prefix/lib/universal.dylib" "$prefix/lib/universal.dylib"
audit universal arm64
echo "Audit tests passed; fixtures and reports: $fixture"
