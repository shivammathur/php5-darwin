#!/usr/bin/env bash
# Revalidate immutable native artifacts without changing their source provenance.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/backports/common.sh
. "$here/common.sh"
mode=${1:?}
destination=${2:?}
run=${CANDIDATE_RUN:?}
revision=${CANDIDATE_SHA:?}
repository=${GITHUB_REPOSITORY:?}
[[ "$run" =~ ^[0-9]+$ && "$revision" =~ ^[0-9a-f]{40}$ ]] || fail 'Invalid candidate run binding'
[[ "$repository" = shivammathur/php5-darwin ]] || fail 'Unexpected candidate repository'
[[ "$mode" = sources || "$mode" = caches ]] || fail 'Expected sources or caches'
review="$RUNNER_TEMP/reuse-candidates"
mkdir -p "$review"
gh api "repos/$repository/actions/runs/$run" > "$review/run.json"
jq -e --arg sha "$revision" --arg repo "$repository" '
  .head_sha == $sha and .repository.full_name == $repo and
  .path == ".github/workflows/cache.yml" and .event == "workflow_dispatch" and
  .status == "completed" and (.conclusion == "success" or .conclusion == "failure")
' "$review/run.json" >/dev/null || fail 'Candidate run does not match the requested completed build'
attempt=$(jq -r .run_attempt "$review/run.json")
gh api "repos/$repository/actions/runs/$run/attempts/$attempt/jobs?per_page=100" > "$review/jobs.json"
gh api "repos/$repository/actions/runs/$run/artifacts?per_page=100" > "$review/artifacts.json"
for version in 53 54 55; do
  for arch in arm64 x86_64; do
    jq -e --arg name "PHP $version $arch" '
      [.jobs[] | select(.name == $name)] | length == 1 and
      all(.[]; .status == "completed" and
        ([.steps[] | select(.name == "Build native PHP and Imagick caches" and .conclusion == "success")] | length == 1))
    ' "$review/jobs.json" >/dev/null || fail "Native compilation did not pass: PHP $version $arch"
  done
done

download_artifact() {
  local name=$1 directory=$2 id digest archive
  jq -e --arg name "$name" --arg sha "$revision" '
    [.artifacts[] | select(.name == $name and .expired == false and .workflow_run.head_sha == $sha)] |
    if length == 1 then .[0] else error("Missing or ambiguous candidate artifact") end
  ' "$review/artifacts.json" > "$review/$name.json"
  id=$(jq -r .id "$review/$name.json")
  digest=$(jq -r '.digest | sub("^sha256:"; "")' "$review/$name.json")
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Missing artifact digest'
  archive="$review/$id.zip"
  curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' \
    -H "Authorization: Bearer ${GH_TOKEN:?}" \
    "https://api.github.com/repos/$repository/actions/artifacts/$id/zip" -o "$archive"
  verify_sha256 "$archive" "$digest"
  unzip -t "$archive" > "$review/$name-integrity.txt"
  unzip -Z1 "$archive" | awk '
    /^\// { exit 1 }
    { n=split($0,p,"/"); for(i=1;i<=n;i++) if(p[i]=="..") exit 1 }
  ' || fail 'Unsafe artifact path'
  [[ ! -e "$directory" ]] || fail "Artifact destination already exists: $directory"
  mkdir -p "$directory"
  unzip -q "$archive" -d "$directory"
}

if [[ "$mode" = sources ]]; then
  download_artifact backport-source-inputs "$destination"
  cp "$review/run.json" "$destination/candidate-run.json"
  cp "$review/backport-source-inputs.json" "$destination/candidate-source-artifact.json"
  exit 0
fi

version=${PHP_VERSION:?}
version=${version/./}
minor="${version:0:1}.${version:1:1}"
arch=${EXPECTED_ARCHITECTURE:?}
[[ "$(uname -m)" = "$arch" ]] || fail 'Candidate architecture does not match the native runner'
name="php$version-caches-$arch"
candidate="$review/candidate"
download_artifact "$name" "$candidate"
manifest=$(find "$candidate" -type f \( -name sources.json -o -name public-sources.json \))
bootstrap=$(find "$candidate" -type f -name source-bootstrap.json)
[[ -f "$manifest" && -f "$bootstrap" ]] || fail 'Missing or ambiguous source evidence'
projection='{repository, extensions, sources: (.sources | with_entries(.value |= {version,branch,commit,url,sha256,root}))}'
diff -u <(jq -S "$projection" "$RUNNER_TEMP/source-inputs/manifest.json") <(jq -S "$projection" "$manifest")
jq -e --arg sha "${SOURCE_SHA256:?}" '
  .original_sha256 == $sha and .original_files_unchanged == true and (.generated_parsers | length) == 4
' "$bootstrap" >/dev/null || fail 'Candidate source bootstrap does not match the source archive'
[[ "$(jq -r --arg minor "$minor" '.sources[$minor].commit' "$manifest")" = "${SOURCE_COMMIT:?}" ]] || fail 'Candidate source revision mismatch'
command -v zstd >/dev/null || brew install zstd
mkdir -p "$destination" "$RUNNER_TEMP/audit/source" "$RUNNER_TEMP/audit/reuse" "$RUNNER_TEMP/native-build"
suffix=''; [[ "$arch" != arm64 ]] || suffix=-arm64
count=$(find "$candidate" -type f -name '*.tar.zst' | wc -l | tr -d '[:space:]')
[[ "$count" = 2 ]] || fail 'Expected exactly the base and Imagick caches'
for asset in "php$version$suffix-cache.tar.zst" "php$version-imagick$suffix-cache.tar.zst"; do
  path=$(find "$candidate" -type f -name "$asset")
  [[ -f "$path" ]] || fail "Missing or ambiguous cache: $asset"
  zstd -t "$path"
  cp "$path" "$destination/"
done
for part in base imagick; do
  path=$(find "$candidate" -type f -name "$part-manifest.json")
  [[ -f "$path" ]] || fail "Missing or ambiguous $part dependency manifest"
  cp "$path" "$RUNNER_TEMP/native-build/"
done
cp "$manifest" "$RUNNER_TEMP/audit/source/sources.json"
cp "$bootstrap" "$RUNNER_TEMP/audit/source/source-bootstrap.json"
cp "$review/run.json" "$review/jobs.json" "$review/$name.json" "$review/$name-integrity.txt" "$RUNNER_TEMP/audit/reuse/"
shasum -a 256 "$destination"/*.tar.zst > "$RUNNER_TEMP/audit/reuse/SHA256SUMS"
