#!/bin/bash -e

required_env_vars=(
    "K8S_VERSION"
    "SKU_TEMPLATE_FILE"
    "AZURE_TENANT_ID"
    "AZURE_CLIENT_ID"
    "AZURE_CLIENT_SECRET"
    "PUBLISHER"
    "OFFER"
)

for v in "${required_env_vars[@]}"
do
    if [ -z "${!v}" ]; then
        echo "$v was not set!"
        exit 1
    fi
done

if [ ! -f "$SKU_TEMPLATE_FILE" ]; then
    echo "Could not find sku template file: ${SKU_TEMPLATE_FILE}!"
    exit 1
fi

IFS='.' # set period (.) as delimiter
read -ra ADDR <<< "${K8S_VERSION}" # str is read into an array as tokens separated by IFS
IFS=' ' # reset to default value after usage

major=${ADDR[0]}
minor=${ADDR[1]}
patch=${ADDR[2]}

sku_id="k8s-${major}dot${minor}dot${patch}-ubuntu-1804"

< $SKU_TEMPLATE_FILE sed s/{{ID}}/"$sku_id"/ | sed s/{{K8S_VERSION}}/"$K8S_VERSION/" > sku.json
cat sku.json

echo
echo "Getting pub..."
(set -x ; curl -fsSL https://github.com/devigned/pub/releases/download/v0.2.0/pub_v0.2.0_linux_amd64.tar.gz -o pub; tar -xzf pub)

echo "Creating new SKU"
(set -x ; ./pub_linux_amd64 skus put -p $PUBLISHER -o "$OFFER" -f sku.json ; echo "")

echo "Writing publishing info"
cat <<EOF > sku-publishing-info.json
{
    "publisher" : "$PUBLISHER",
    "offer" : "$OFFER",
    "sku_id" : "$sku_id",
    "k8s_version" : "$K8S_VERSION"
}
EOF

cat sku-publishing-info.json