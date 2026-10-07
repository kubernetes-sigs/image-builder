#!/usr/bin/env bash

set -euo pipefail

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir "$root/bin"
printf '%s\n' '$SSH_PASSWORD' '$ENCRYPTED_SSH_PASSWORD' > "$root/user-data.tmpl"
printf 'old rendered content\n' > "$root/user-data"

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/set-ssh-password.sh"

PACKER_DIR="$root" "$script" >/dev/null
grep -qv '\$SSH_PASSWORD\|\$ENCRYPTED_SSH_PASSWORD' "$root/user-data"

printf '%s\n' '$SSH_PASSWORD' '$ENCRYPTED_SSH_PASSWORD' > "$root/user-data.tmpl"
printf 'preserve this content\n' > "$root/user-data"
cat > "$root/bin/sed" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$root/bin/sed"
if PATH="$root/bin:/usr/bin:/bin" PACKER_DIR="$root" "$script" >/dev/null 2>&1; then
  echo "expected rendering failure" >&2
  exit 1
fi
grep -q '^preserve this content$' "$root/user-data"

printf '%s\n' '$SSH_PASSWORD' '$ENCRYPTED_SSH_PASSWORD' > "$root/user-data.tmpl"
PACKER_DIR="$root" "$script" >/dev/null & first=$!
PACKER_DIR="$root" "$script" >/dev/null & second=$!
wait "$first"
wait "$second"
grep -qv '\$SSH_PASSWORD\|\$ENCRYPTED_SSH_PASSWORD' "$root/user-data"

echo "set-ssh-password atomic rendering checks passed"
