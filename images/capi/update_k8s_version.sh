#!/bin/sh

UBUNTU_FILE=$(find ./images/capi/packer -name "ubuntu-2404.json" | head -n 1)

if [ -z "$UBUNTU_FILE" ]; then
    echo "Error: ubuntu-2404.json file could not be found."
    exit 1
fi

echo "Using ubuntu-2404.json at $UBUNTU_FILE"

K8S_VERSION="${K8S_VERSION:-1.30.10}" # Default to 1.30.10 if not provided

echo "Adding kubernetes_semver: $K8S_VERSION to $UBUNTU_FILE"

jq --arg k8s_version "$K8S_VERSION" '.kubernetes_semver = $k8s_version' "$UBUNTU_FILE" > "$UBUNTU_FILE.tmp" && mv "$UBUNTU_FILE.tmp" "$UBUNTU_FILE"

AWS_PROFILE_ENV="${AWS_PROFILE}"
AWS_PROFILE_FILE=$(jq -r '.aws_profile' "$UBUNTU_FILE")

if [ "$AWS_PROFILE_ENV" != "$AWS_PROFILE_FILE" ]; then
    echo "AWS profile mismatch. Updating aws_profile in $UBUNTU_FILE to match $AWS_PROFILE_ENV."
    jq --arg aws_profile "$AWS_PROFILE_ENV" '.aws_profile = $aws_profile' "$UBUNTU_FILE" > "$UBUNTU_FILE.tmp" && mv "$UBUNTU_FILE.tmp" "$UBUNTU_FILE"
else
    echo "AWS profile matches: $AWS_PROFILE_ENV"
fi