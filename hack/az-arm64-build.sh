export USE_AZURE_CLI_AUTH=true
export AZURE_SUBSCRIPTION_ID=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
export AZURE_LOCATION=centralus
export RESOURCE_GROUP_NAME=alexbenn-test-arm64-image-build

DATE=$(date +%Y%m%d)
SEQNUM=01
SEQNUM_FILE=/tmp/az-arm64-build-seqnum-$DATE.txt
if [ -f $SEQNUM_FILE ]; then
    SEQNUM=$(cat $SEQNUM_FILE)
    SEQNUM=$((10#$SEQNUM + 1))
    if [ $SEQNUM -lt 10 ]; then
        SEQNUM="0$SEQNUM"
    fi
fi
echo $SEQNUM > $SEQNUM_FILE

make build-azure-sig-ubuntu-2404-arm64-gen2 2>&1 | tee /tmp/build-azure-sig-ubuntu-2404-arm64-gen2-$DATE-$SEQNUM.out
