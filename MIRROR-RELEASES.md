# Mirror published GitHub releases

`.github/workflows/mirror-github-releases.yml` is manual only. It copies already
published release assets using the existing repository secrets. Pushing this
branch does not publish anything. The workflow must be present on the default
branch before GitHub exposes a new manual workflow; this branch is preparation
only and does not change the default branch.

Destination: Cloudsmith `shivammathur/php5-darwin`.

`php-versions` accepts `all` or space-separated minor versions from:
`5.3 5.4 5.5`. Each version runs in its own parallel job, with
`fail-fast: false` and no `max-parallel` cap. Duplicate jobs for the same version
share a concurrency group. GitHub account concurrency limits still apply.

The workflow reads GitHub Releases, pins selected asset IDs, sizes and SHA256
digests, downloads on the Actions runner, verifies every byte and rejects source
changes observed during download. Missing assets or GitHub digests stop the job.
It never builds, repackages, runs PHP, changes GitHub releases, accesses private
build storage, deletes mirror objects or transfers build payloads locally.
Transfer receipts are retained as Actions artifacts, including partial failure
receipts. `mirror_verified` appears only after destination verification passes.

Each version copies exactly four caches: Intel/ARM64 runtime and Imagick.
The shared job copies GitHub's installer once after the version jobs succeed.
Cloudsmith downloads are SHA256-verified with bounded propagation retries.
