#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for tool in mke2fs debugfs; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "SKIP: ${tool} is required for sysext layer helper smoke test" >&2
    exit 0
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

rootfs="${workdir}/rootfs"
mkdir -p "${rootfs}/usr/share/sysext-test"
printf 'ok\n' > "${rootfs}/usr/share/sysext-test/payload"

raw="$("${script_dir}/build-sysext-layer.sh" \
  --name sysext-test \
  --version v1.2.3 \
  --rootfs "${rootfs}" \
  --output-dir "${workdir}/out" \
  --arch x86_64)"

expected="/usr/lib/extension-release.d/extension-release.sysext-test-v1.2.3-x86-64"
if ! debugfs -R "stat ${expected}" "${raw}" >/dev/null 2>&1; then
  echo "missing expected extension-release metadata: ${expected}" >&2
  exit 1
fi

echo "sysext layer helper smoke test passed"
