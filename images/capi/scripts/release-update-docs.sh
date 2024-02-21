#!/bin/bash

set -o errexit
set -o pipefail

OLD_VERSION=$(git tag --list | sort -V | tail -2 | head -1)
OLD_VERSION=${OLD_VERSION#v}
CURRENT_VERSION=$(git tag --list | sort -V | tail -1)
CURRENT_VERSION=${CURRENT_VERSION#v}
NEXT_VERSION=$(echo ${CURRENT_VERSION} | awk -F. -v OFS=. '{$NF += 1 ; print}')
NEXT_VERSION=${NEXT_VERSION#v}

OLD_DATE=$(git log -1 --format=%aI v${OLD_VERSION})
OLD_DATE=$(date -d${OLD_DATE} '+%B %-d, %Y')
TODAY_DATE=$(date '+%B %-d, %Y')

# First update the example to suggest the next patch tag
sed -i "s/${CURRENT_VERSION}/${NEXT_VERSION}/g" docs/book/src/capi/releasing.md

# Then update all references to the previous tag
sed -i "s/${OLD_VERSION}/${CURRENT_VERSION}/g" RELEASE.md
sed -i "s/${OLD_VERSION}/${CURRENT_VERSION}/g" docs/book/src/capi/releasing.md
sed -i "s/${OLD_VERSION}/${CURRENT_VERSION}/g" docs/book/src/capi/container-image.md

# Finally update the dates
sed -i "s/${OLD_DATE}/${TODAY_DATE}/g" RELEASE.md
sed -i "s/${OLD_DATE}/${TODAY_DATE}/g" docs/book/src/capi/releasing.md
