#!/bin/bash -e

[[ -n ${DEBUG:-} ]] && set -o xtrace

echo "PWD: $PWD"

OS=${OS:-"Ubuntu"}
OS_VERSION=${OS_VERSION:-"22.04"}
PUB_VERSION=${PUB_VERSION:-"v0.3.3"}

required_env_vars=(
    "AZURE_CLIENT_ID"
    "AZURE_CLIENT_SECRET"
    "AZURE_TENANT_ID"
    "OS"
    "OS_VERSION"
    "PUB_VERSION"
)

for v in "${required_env_vars[@]}"
do
    if [ -z "${!v}" ]; then
        echo "$v was not set!"
        exit 1
    fi
done

SKU_INFO="sku/sku-publishing-info.json"
VHD_INFO="vhd/vhd-publishing-info.json"

required_files=(
    "SKU_INFO"
    "VHD_INFO"
)

for f in "${required_files[@]}"
do
    if [ ! -f "${!f}" ]; then
        echo "could not find file: ${!f}"
        exit 1
    fi
done

echo "Getting pub..."
(set -x ; curl -fsSL https://github.com/devigned/pub/releases/download/${PUB_VERSION}/pub_${PUB_VERSION}_linux_amd64.tar.gz -o pub; tar -xzf pub)

echo "SKU publishing info:"
cat $SKU_INFO
echo

echo "VHD publishing info:"
cat $VHD_INFO
echo


# get Kubernetes version and split into major, minor, and patch
k8s_version=$(< $SKU_INFO jq -r ".k8s_version")
IFS='.' # set period (.) as delimiter
read -ra ADDR <<< "${k8s_version}" # str is read into an array as tokens separated by IFS
IFS=' ' # reset to default value after usage
major=${ADDR[0]}
minor=${ADDR[1]}
patch=${ADDR[2]}

# generate image version
image_version=${major}${minor}.${patch}.$(date +"%Y%m%d")

# generate media name
sku_id=$(< $SKU_INFO jq -r ".sku_id")
media_name="${sku_id}-${image_version}"

# generate published date
published_date=$(date +"%m/%d/%Y")

# get vhd url
vhd_url=$(< $VHD_INFO jq -r ".vhd_url")

label="Kubernetes $k8s_version $OS $OS_VERSION"
description="Kubernetes $k8s_version $OS $OS_VERSION"

# create version.json
cat <<EOF > version.json
{
    "$image_version" : {
        "mediaName": "$media_name",
        "showInGui": false,
        "publishedDate": "$published_date",
        "label": "$label",
        "description": "$description",
        "osVHdUrl": "$vhd_url"
    }
}
EOF

echo "Version info:"
cat version.json

publisher=$(< $SKU_INFO jq -r ".publisher")
offer=$(< $SKU_INFO jq -r ".offer")
sku=$(< $SKU_INFO jq -r ".sku_id")

# TODO: Update pub versions put to take in version.json as a file
echo "Create new disk version"
set -x
./pub_linux_amd64 versions put corevm -p $publisher -o $offer -s $sku --version $image_version --vhd-uri $vhd_url --media-name $media_name --label "$label" --desc "$description" --published-date "$published_date"
set +x
echo -e "\nCreated disk version"
