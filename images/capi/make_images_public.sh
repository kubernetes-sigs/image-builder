#!/bin/bash

set -euo pipefail

CLOUD="${CLOUD:-aws}"

# Find the manifest file
if [ -f "./output/packer-manifest.json" ]; then
    PACKER_MANIFEST_PATH="./output/packer-manifest.json"
else
    echo "Searching for packer-manifest.json in the current directory..."
    PACKER_MANIFEST_PATH=$(find . -name "packer-manifest.json" | head -n 1)
    if [ -z "$PACKER_MANIFEST_PATH" ]; then
        echo "Error: packer-manifest.json file could not be found."
        exit 1
    fi
fi

echo "Using packer-manifest.json at $PACKER_MANIFEST_PATH"

case "$CLOUD" in
  aws)
    # AWS-specific block to make AMIs public
    # Initialize arrays
    REGIONS=()
    AMI_IDS=()

    jq -c '.builds[]' < "$PACKER_MANIFEST_PATH" | while read -r BUILD; do
        ARTIFACT=$(echo "$BUILD" | jq -r '.artifact_id')
        # echo "Processing artifact: $ARTIFACT"
        # Split ARTIFACT into separate strings using "," as the separator
        IFS=',' read -ra ARTIFACT_PARTS <<< "$ARTIFACT"

        for PART in "${ARTIFACT_PARTS[@]}"; do
            # Further split each value into two strings using ":" as the separator
            IFS=':' read -r PART_LEFT PART_RIGHT <<< "$PART"

            # Convert the split string into JSON with part_left as the key and part_right as the value
            JSON_ENTRY="{\"$PART_LEFT\": \"$PART_RIGHT\"}"
            # Validate the JSON entry
            if echo "$JSON_ENTRY" | jq empty > /dev/null 2>&1; then
                # Append the region and AMI ID to their respective arrays
                REGIONS+=("$PART_LEFT")
                AMI_IDS+=("$PART_RIGHT")
            else
                echo "Warning: Invalid JSON entry: $JSON_ENTRY"
            fi
        done
        
        # Create a JSON object with regions and ami_ids arrays
        FINAL_JSON=$(jq -n \
            --argjson regions "$(printf '%s\n' "${REGIONS[@]}" | jq -R . | jq -s .)" \
            --argjson ami_ids "$(printf '%s\n' "${AMI_IDS[@]}" | jq -R . | jq -s .)" \
            '{regions: $regions, ami_ids: $ami_ids}')

        # Loop through the regions and AMI IDs
        for i in "${!REGIONS[@]}"; do
            # Get the region and AMI ID for the current index
            REGION="${REGIONS[$i]}"
            AMI_ID="${AMI_IDS[$i]}"

            # Disable block public access for the AMI
            echo "Disabling block public access for AMI $AMI_ID in region $REGION."
            aws ec2 disable-image-block-public-access --region "$REGION"

            # Make the AMI public in the specified region
            echo "Making AMI $AMI_ID public in region $REGION"
            
            # Make the AMI public
            aws ec2 modify-image-attribute --image-id "$AMI_ID" --launch-permission "Add=[{Group=all}]" --region "$REGION"
        done

        # Verify all AMI IDs in their respective regions are public
        for i in "${!AMI_IDS[@]}"; do
            AMI_ID="${AMI_IDS[$i]}"
            REGION="${REGIONS[$i]}"
            PUBLIC_STATE=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI_ID" --query "Images[0].Public" --output text)
            if [ "$PUBLIC_STATE" != "True" ]; then
                echo "Error: AMI $AMI_ID in region $REGION is not public."
                exit 1
            fi
            echo "Verified: AMI $AMI_ID in region $REGION is public."
        done
    done
    ;;
  
  gcp)
    # GCP-specific block to make images public
    PROJECT_ID="${GCP_PROJECT_ID:-byoc-dev-459905}"
    
    # Extract image names from the manifest
    IMAGE_NAMES=$(jq -r '.builds[] | select(.builder_type=="googlecompute") | .artifact_id' "$PACKER_MANIFEST_PATH" | cut -d':' -f2)

    if [ -z "$IMAGE_NAMES" ]; then
        echo "No GCP images found in manifest."
        exit 0
    fi

    for IMAGE in $IMAGE_NAMES; do
        echo "Making GCP image $IMAGE public in project $PROJECT_ID"
        gcloud compute images add-iam-policy-binding "$IMAGE" \
            --project="$PROJECT_ID" \
            --member='allAuthenticatedUsers' \
            --role='roles/compute.imageUser'
    done

    for IMAGE in $IMAGE_NAMES; do
        echo "Verifying if GCP image $IMAGE is public in project $PROJECT_ID"
        POLICY=$(gcloud compute images get-iam-policy "$IMAGE" --project="$PROJECT_ID" --format=json)
        if echo "$POLICY" | jq -e '.bindings[] | select(.role=="roles/compute.imageUser") | .members[] | select(.=="allAuthenticatedUsers")' > /dev/null; then
            echo "Image $IMAGE is public."
        else
            echo "Warning: Image $IMAGE is NOT public."
        fi
    done
    ;;
  
  azure)
    # Azure-specific block to make images public
    RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-capi-images}"
    
    # Extract image names from the manifest
    IMAGE_NAMES=$(jq -r '.builds[] | select(.builder_type=="azure-arm") | .artifact_id' "$PACKER_MANIFEST_PATH")

    if [ -z "$IMAGE_NAMES" ]; then
        echo "No Azure images found in manifest."
        exit 0
    fi

    for IMAGE in $IMAGE_NAMES; do
        echo "Making Azure image $IMAGE public in resource group $RESOURCE_GROUP"
        # Note: Azure doesn't have a direct "make public" command like AWS/GCP
        # We will need to share to specific subscriptions or use Shared Image Gallery
        echo "Azure image sharing requires manual configuration or Shared Image Gallery setup."
        echo "Image $IMAGE is ready for sharing configuration."
    done
    ;;
  
  *)
    echo "Unknown CLOUD value: $CLOUD"
    exit 1
    ;;
esac

echo "Image public configuration completed for $CLOUD."