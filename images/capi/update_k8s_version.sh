#!/bin/sh

K8S_VERSION="${K8S_VERSION:-1.30.10}" # Default to 1.30.10 if not provided

CLOUD="${CLOUD:-aws}"

case "$CLOUD" in
  aws)
    # AWS-specific block to update AWS packer file
    AWS_FILE=$(find ./images/capi/packer/ami -name "ubuntu-2404.json" | head -n 1)

    if [ -z "$AWS_FILE" ]; then
        echo "Error: ubuntu-2404.json file could not be found."
        exit 1
    fi

    echo "Using ubuntu-2404.json at $AWS_FILE"
    echo "Adding kubernetes_semver: $K8S_VERSION to $AWS_FILE"

    jq --arg k8s_version "$K8S_VERSION" '.kubernetes_semver = $k8s_version' "$AWS_FILE" > "$AWS_FILE.tmp" && mv "$AWS_FILE.tmp" "$AWS_FILE"

    AWS_PROFILE_ENV="${AWS_PROFILE}"
    AWS_PROFILE_FILE=$(jq -r '.aws_profile' "$AWS_FILE")

    if [ "$AWS_PROFILE_ENV" != "$AWS_PROFILE_FILE" ]; then
        echo "AWS profile mismatch. Updating aws_profile in $AWS_FILE to match $AWS_PROFILE_ENV."
        jq --arg aws_profile "$AWS_PROFILE_ENV" '.aws_profile = $aws_profile' "$AWS_FILE" > "$AWS_FILE.tmp" && mv "$AWS_FILE.tmp" "$AWS_FILE"
    else
        echo "AWS profile matches: $AWS_PROFILE_ENV"
    fi
    ;;
  gcp)
    # GCP-specific block to update GCP packer file
    GCP_FILE=$(find ./images/capi/packer/gce -name "ubuntu-2404.json" | head -n 1)
    if [ -z "$GCP_FILE" ]; then
        echo "Error: GCP ubuntu-2404.json file could not be found."
        exit 1
    fi
    echo "Using GCP ubuntu-2404.json at $GCP_FILE"
    echo "Adding kubernetes_semver: $K8S_VERSION to $GCP_FILE"
    jq --arg k8s_version "$K8S_VERSION" '.kubernetes_semver = $k8s_version' "$GCP_FILE" > "$GCP_FILE.tmp" && mv "$GCP_FILE.tmp" "$GCP_FILE"
    ;;
  azure)
    # Azure-specific block to update Azure packer file
    AZURE_FILE=$(find ./images/capi/packer/azure -name "ubuntu-2404.json" | head -n 1)
    if [ -z "$AZURE_FILE" ]; then
        echo "Error: Azure ubuntu-2404.json file could not be found."
        exit 1
    fi
    echo "Using Azure ubuntu-2404.json at $AZURE_FILE"
    echo "Adding kubernetes_semver: $K8S_VERSION to $AZURE_FILE"
    jq --arg k8s_version "$K8S_VERSION" '.kubernetes_semver = $k8s_version' "$AZURE_FILE" > "$AZURE_FILE.tmp" && mv "$AZURE_FILE.tmp" "$AZURE_FILE"
    ;;
  *)
    echo "Unknown CLOUD value: $CLOUD"
    exit 1
    ;;
esac