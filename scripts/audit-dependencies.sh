#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

prefix=${1:-/opt/local}
required_arch=${2:-x86_64}
report_dir=${AUDIT_DIR:-$(mktemp -d)}
mach_o_files="$report_dir/mach-o-files.txt"
dependencies="$report_dir/opt-local-dependencies.txt"
missing="$report_dir/missing-dependencies.txt"
wrong_arch="$report_dir/wrong-architecture.txt"

mkdir -p "$report_dir"
: >"$mach_o_files"
: >"$dependencies"
: >"$missing"
: >"$wrong_arch"

for directory in "$prefix/bin" "$prefix/sbin" "$prefix/lib" "$prefix/libexec"; do
  [[ -d "$directory" ]] || continue
  find "$directory" -type f \( -perm -111 -o -name '*.dylib' -o -name '*.so' \) -print
done | sort -u | while IFS= read -r file_path; do
  description=$(file "$file_path")
  [[ "$description" == *Mach-O* ]] || continue
  printf '%s\n' "$file_path" >>"$mach_o_files"
  if [[ "$description" != *"$required_arch"* && "$description" != *universal* ]]; then
    printf '%s\t%s\n' "$file_path" "$description" >>"$wrong_arch"
  fi
  otool -L "$file_path" 2>/dev/null | awk '/^[[:space:]]+\/opt\/local\// {print $1}' >>"$dependencies"
done
sort -u -o "$dependencies" "$dependencies"

while IFS= read -r dependency; do
  if [[ ! -e "$dependency" ]]; then
    printf '%s\n' "$dependency" >>"$missing"
  elif ! file -L "$dependency" | grep -Eq "$required_arch|universal binary"; then
    printf '%s\t%s\n' "$dependency" "$(file -L "$dependency")" >>"$wrong_arch"
  fi
done <"$dependencies"

if [[ -s "$missing" || -s "$wrong_arch" ]]; then
  [[ ! -s "$missing" ]] || { echo 'Missing Mach-O dependencies:' >&2; cat "$missing" >&2; }
  [[ ! -s "$wrong_arch" ]] || { echo 'Wrong-architecture Mach-O files:' >&2; cat "$wrong_arch" >&2; }
  exit 1
fi

echo "Audited $(wc -l <"$mach_o_files" | tr -d ' ') Mach-O files and $(wc -l <"$dependencies" | tr -d ' ') /opt/local dependencies"
