#!/usr/bin/env bash

set -euo pipefail

missing=()
for tool in mke2fs find stat; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    missing+=("${tool}")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required sysext tooling: ${missing[*]}" >&2
  echo "Install e2fsprogs/coreutils or provide equivalent tools in PATH." >&2
  exit 1
fi
