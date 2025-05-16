#!/bin/bash

set -euo pipefail

# Variables
AWS_REGION="us-east-1" # Change this to your desired region
CLUSTER_NAMES=("cluster1" "cluster2") # List of cluster names to check
AMI_TAG_KEY="k8s-version" # Tag key used to identify Kubernetes version on AMIs
DRY_RUN=true # Set to false to actually delete AMIs

# Function to get the Kubernetes versions of live clusters
get_live_k8s_versions() {
    local live_versions=()
    for cluster in "${CLUSTER_NAMES[@]}"; do
        version=$(kubectl --kubeconfig="/path/to/${cluster}/kubeconfig" version --short | grep "Server Version" | awk '{print $3}')
        live_versions+=("$version")
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
    echo "Fetching live Kubernetes versions..."
    live_versions=$(get_live_k8s_versions)
    echo "Live Kubernetes versions: $live_versions"

    echo "Fetching AMIs with tag key '$AMI_TAG_KEY'..."
    amis=$(list_amis_with_tag)

    echo "Processing AMIs..."
    for ami in $(echo "$amis" | jq -c '.[]'); do
        ami_id=$(echo "$ami" | jq -r '.[0]')
        ami_version=$(echo "$ami" | jq -r '.[1]')

        if [[ ! " ${live_versions[@]} " =~ " ${ami_version} " ]]; then
            echo "AMI $ami_id with Kubernetes version $ami_version is outdated."
            delete_ami "$ami_id"
        else
            echo "AMI $ami_id with Kubernetes version $ami_version is still in use."
        fi
    done
}

main