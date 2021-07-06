#!/bin/bash -e

OS=${OS:-"Ubuntu"}
OS_VERSION=${OS_VERSION:-"18.04"}
[[ -n ${DEBUG:-} ]] && set -o xtrace

required_env_vars=(
    "KUBERNETES_VERSION"
    "SKU_TEMPLATE_FILE"
    "AZURE_TENANT_ID"
    "AZURE_CLIENT_ID"
    "AZURE_CLIENT_SECRET"
    "PUBLISHER"
    "OFFER"
    "OS"
    "OS_VERSION"
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
read -ra ADDR <<< "${KUBERNETES_VERSION}" # str is read into an array as tokens separated by IFS
IFS=' ' # reset to default value after usage

major=${ADDR[0]}
minor=${ADDR[1]}
patch=${ADDR[2]}

os=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
version=$(echo "$OS_VERSION" | tr '[:upper:]' '[:lower:]' | tr -d .)
sku_id="k8s-${major}dot${minor}dot${patch}-${os}-${version}"

if [ "$OS" == "Ubuntu" ]; then
    os_type="Ubuntu"
    os_family="Linux"
elif [ "$OS" == "Windows" ]; then
    os_type="Other"
    os_family="Windows"
else
    echo "Cannot configure unknown OS: ${OS}!"
    exit 1
fi

< $SKU_TEMPLATE_FILE sed s/{{ID}}/"$sku_id"/ \
    | sed s/{{KUBERNETES_VERSION}}/"$KUBERNETES_VERSION/" \
    | sed s/{{OS}}/"$OS/" \
    | sed s/{{OS_VERSION}}/"$OS_VERSION/" \
    | sed s/{{OS_TYPE}}/"$os_type/" \
    | sed s/{{OS_FAMILY}}/"$os_family/" \
    > sku.json
cat sku.json

echo
echo "Getting pub..."
(set -x ; curl -fsSL https://github.com/devigned/pub/releases/download/v0.3.2/pub_v0.3.2_linux_amd64.tar.gz -o pub; tar -xzf pub)

echo "Creating new SKU"
set -x
./pub_linux_amd64 skus put -p $PUBLISHER -o "$OFFER" -f sku.json
set +x
echo -e "\nCreated sku"

echo "Writing publishing info"
cat <<EOF > sku-publishing-info.json
{
    "publisher" : "$PUBLISHER",
    "offer" : "$OFFER",
    "sku_id" : "$sku_id",
    "k8s_version" : "$KUBERNETES_VERSION"
}
EOF

cat sku-publishing-info.json
