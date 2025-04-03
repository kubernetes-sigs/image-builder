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
                 
                 # Output the JSON object
               #   echo "$FINAL_JSON"

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

              # Verify all AMI IDs in the region are public
              for AMI_ID in $AMI_IDS; do
               PUBLIC_STATE=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI_ID" --query "Images[0].Public" --output text)
               if [ "$PUBLIC_STATE" != "True" ]; then
                 echo "Error: AMI $AMI_ID in region $REGION is not public."
                 exit 1
               fi
               echo "Verified: AMI $AMI_ID in region $REGION is public."
              done

   done             
   