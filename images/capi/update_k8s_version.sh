#!/bin/bash

set -euo pipefail

CLOUD="${CLOUD:-aws}"
K8S_VERSION="${K8S_VERSION:-1.31.4}"

# Extract kubernetes series from version (e.g., "1.30.10" -> "v1.30")
K8S_SERIES="v$(echo "$K8S_VERSION" | cut -d. -f1,2)"

# Set crictl version to match kubernetes version
CRICTL_VERSION="$K8S_VERSION"

# Set deb version with package suffix
K8S_DEB_VERSION="${K8S_VERSION}-1.1"

# Set rpm version (same as semver without 'v')
K8S_RPM_VERSION="$K8S_VERSION"

# Set semver with 'v' prefix
K8S_SEMVER="v$K8S_VERSION"

echo "Updating Kubernetes versions:"
echo "  kubernetes_semver: $K8S_SEMVER"
echo "  kubernetes_series: $K8S_SERIES"
echo "  kubernetes_deb_version: $K8S_DEB_VERSION"
echo "  kubernetes_rpm_version: $K8S_RPM_VERSION"
echo "  crictl_version: $CRICTL_VERSION"

case "$CLOUD" in
  aws)
    # AWS-specific block to update AWS packer file
    AWS_FILE=$(find ./images/capi/packer/ami -name "ubuntu-2404.json" | head -n 1)

    if [ -z "$AWS_FILE" ]; then
        echo "Error: ubuntu-2404.json file could not be found."
        exit 1
    fi

    echo "Using ubuntu-2404.json at $AWS_FILE"
    echo "Updating Kubernetes versions in $AWS_FILE"

    # Update all kubernetes-related versions
    jq --arg k8s_semver "$K8S_SEMVER" \
       --arg k8s_series "$K8S_SERIES" \
       --arg k8s_deb_version "$K8S_DEB_VERSION" \
       --arg k8s_rpm_version "$K8S_RPM_VERSION" \
       --arg crictl_version "$CRICTL_VERSION" \
       '.kubernetes_semver = $k8s_semver | 
        .kubernetes_series = $k8s_series | 
        .kubernetes_deb_version = $k8s_deb_version | 
        .kubernetes_rpm_version = $k8s_rpm_version | 
        .crictl_version = $crictl_version' \
       "$AWS_FILE" > "$AWS_FILE.tmp" && mv "$AWS_FILE.tmp" "$AWS_FILE"

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

    echo "Using ubuntu-2404.json at $GCP_FILE"
    echo "Updating Kubernetes versions in $GCP_FILE"

    # Update all kubernetes-related versions for GCP
    jq --arg k8s_semver "$K8S_SEMVER" \
       --arg k8s_series "$K8S_SERIES" \
       --arg k8s_deb_version "$K8S_DEB_VERSION" \
       --arg k8s_rpm_version "$K8S_RPM_VERSION" \
       --arg crictl_version "$CRICTL_VERSION" \
       '.kubernetes_semver = $k8s_semver | 
        .kubernetes_series = $k8s_series | 
        .kubernetes_deb_version = $k8s_deb_version | 
        .kubernetes_rpm_version = $k8s_rpm_version | 
        .crictl_version = $crictl_version' \
       "$GCP_FILE" > "$GCP_FILE.tmp" && mv "$GCP_FILE.tmp" "$GCP_FILE"

    echo "Updated GCP Kubernetes versions successfully."
    ;;
  
  azure)
    # Azure-specific block to update Azure packer file
    AZURE_FILE=$(find ./images/capi/packer/azure -name "ubuntu-2404.json" | head -n 1)

    if [ -z "$AZURE_FILE" ]; then
        echo "Error: Azure ubuntu-2404.json file could not be found."
        exit 1
    fi

    echo "Using ubuntu-2404.json at $AZURE_FILE"
    echo "Updating Kubernetes versions in $AZURE_FILE"

    # Update all kubernetes-related versions for Azure
    jq --arg k8s_semver "$K8S_SEMVER" \
       --arg k8s_series "$K8S_SERIES" \
       --arg k8s_deb_version "$K8S_DEB_VERSION" \
       --arg k8s_rpm_version "$K8S_RPM_VERSION" \
       --arg crictl_version "$CRICTL_VERSION" \
       '.kubernetes_semver = $k8s_semver | 
        .kubernetes_series = $k8s_series | 
        .kubernetes_deb_version = $k8s_deb_version | 
        .kubernetes_rpm_version = $k8s_rpm_version | 
        .crictl_version = $crictl_version' \
       "$AZURE_FILE" > "$AZURE_FILE.tmp" && mv "$AZURE_FILE.tmp" "$AZURE_FILE"

    echo "Updated Azure Kubernetes versions successfully."
    ;;
  
  *)
    echo "Unknown CLOUD value: $CLOUD"
    exit 1
    ;;
esac

echo "Kubernetes version update completed for $CLOUD."