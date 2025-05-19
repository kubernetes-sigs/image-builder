#!/bin/bash

set -euo pipefail

# Variables
AWS_REGION="us-east-1" # Change this to your desired region
CLUSTER_NAMES=("voy-bootstrap-aws-ditto-test" "valdev-usw2-ditto") # List of cluster names to check
AMI_TAG_KEY="k8s-version" # Tag key used to identify Kubernetes version on AMIs
DRY_RUN=true # Set to false to actually delete AMIs
# Dex OIDC issuer
DEX_ISSUER="https://kubelogin.ops.k8s.ditto.live"


# Example usage:
# To keep additional Kubernetes versions (e.g., 1.21.1 and 1.22.3), pass them as a comma-separated list:
# ./cleanup_outdated_ami.sh --keep-versions 1.21.1,1.22.3
# Global variable for additional versions to keep
KEEP_VERSIONS=()

# Function to parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-versions)
                IFS=',' read -r -a KEEP_VERSIONS <<< "$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

# Function to get the Kubernetes versions of live clusters
get_kubeconfig() {
    local cluster_name=$1
    local kubeconfig_path="/path/to/${cluster_name}/kubeconfig"

    echo "Fetching kubeconfig for cluster: $cluster_name"
    curl -sSL -o "$kubeconfig_path" "https://kubelogin.ops.k8s.ditto.live/clusters/${cluster_name}/kubeconfig"

    if [ ! -f "$kubeconfig_path" ]; then
        echo "Failed to fetch kubeconfig for cluster: $cluster_name"
        exit 1
    fi

    echo "Kubeconfig for cluster $cluster_name saved to $kubeconfig_path"
}

get_live_k8s_versions() {
    local live_versions=()
    echo "Fetching live Kubernetes versions from clusters..."

    for CLUSTER in "${CLUSTER_NAMES[@]}"; do
        echo "----------------------------------------"
        echo "Cluster: $CLUSTER"
        export KUBECONFIG="~/.kube/${CLUSTER}/config"  # Adjust to your kubeconfig location

        # Use kubelogin to authenticate (if needed)
        kubelogin convert-kubeconfig -i $DEX_ISSUER --kubeconfig $KUBECONFIG

        # Get server version from live cluster
        VERSION=$(kubectl version --short --kubeconfig $KUBECONFIG | grep "Server Version" | awk '{print $3}')

        if [ -z "$VERSION" ]; then
            echo "❌ Failed to fetch version from $CLUSTER"
        else
            echo "✅ Kubernetes Version: $VERSION"
            live_versions+=("$VERSION")
        fi
    done
    echo "${live_versions[@]}"
}

# Function to list AMIs with the specified tag key
list_amis_with_tag() {
    aws ec2 describe-images --region "$AWS_REGION" --owners self \
        --filters "Name=tag-key,Values=$AMI_TAG_KEY" \
        --query "Images[*].[ImageId,Tags[?Key=='$AMI_TAG_KEY'].Value | [0]]" \
        --output json
}

# Function to delete an AMI
delete_ami() {
    local ami_id=$1
    echo "Deleting AMI: $ami_id"
    if [ "$DRY_RUN" = false ]; then
        aws ec2 deregister-image --image-id "$ami_id" --region "$AWS_REGION"
    else
        echo "[DRY RUN] Would delete AMI: $ami_id"
    fi
}

# Main logic
main() {
    parse_args "$@"

    echo "Fetching live Kubernetes versions..."
    live_versions=$(get_live_k8s_versions)
    echo "Live Kubernetes versions: $live_versions"

    echo "Additional versions to keep: ${KEEP_VERSIONS[*]}"

    echo "Fetching AMIs with tag key '$AMI_TAG_KEY'..."
    amis=$(list_amis_with_tag)

    echo "Processing AMIs..."
    for ami in $(echo "$amis" | jq -c '.[]'); do
        ami_id=$(echo "$ami" | jq -r '.[0]')
        ami_version=$(echo "$ami" | jq -r '.[1]')

        if [[ ! " ${live_versions[@]} ${KEEP_VERSIONS[@]} " =~ " ${ami_version} " ]]; then
            echo "AMI $ami_id with Kubernetes version $ami_version is outdated."
            # delete_ami "$ami_id"
        else
            echo "AMI $ami_id with Kubernetes version $ami_version is still in use."
        fi
    done
}

main "$@"