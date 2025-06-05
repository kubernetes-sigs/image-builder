#!/bin/bash
set -euo pipefail

OSCAP_VERSION=0.1.76
OSCAP_URL="https://github.com/ComplianceAsCode/content/releases/download/v${OSCAP_VERSION}/scap-security-guide-${OSCAP_VERSION}.zip"
DEST_DIR="/opt/ssg"

echo ">> Creating SSG directory: $DEST_DIR"
sudo mkdir -p "$DEST_DIR"
sudo chmod 755 "$DEST_DIR"

echo ">> Downloading SSG content"
curl -L -o /tmp/ssg.zip "$OSCAP_URL"

echo ">> Unzipping SSG content"
sudo unzip -oq /tmp/ssg.zip -d "$DEST_DIR"

PLAYBOOK_PATH=$(find "$DEST_DIR" -name "ubuntu2404-playbook-cis_level1_server.yml")

if [[ -z "$PLAYBOOK_PATH" ]]; then
  echo "!! Could not find playbook. Exiting."
  exit 1
fi

echo ">> Found playbook: $PLAYBOOK_PATH"
echo ">> Patching playbook to fix 'NetworkManager' package name"

# Cross-platform sed
if [[ "$OSTYPE" == "darwin"* ]]; then
 sudo sed -i '' 's/NetworkManager/network-manager/g' "$PLAYBOOK_PATH"
else
  sudo sed -i 's/NetworkManager/network-manager/g' "$PLAYBOOK_PATH"
fi

echo ">> Patch complete. Verifying change:"
grep -i 'network-manager' "$PLAYBOOK_PATH" || echo "!! Patch verification failed"
echo ">> Playbook patched successfully."
