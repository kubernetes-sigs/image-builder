#!/bin/bash

echo "OUTPUT_DIR:$OUTPUT_DIR"
echo "ARTIFACT_NAME:$ARTIFACT_NAME"
echo "########"
env
cd $OUTPUT_DIR

echo "FROM registry.access.redhat.com/ubi8/ubi:latest AS builder                                                
ADD --chown=107:107 $ARTIFACT_NAME /disk/image.qcow2                                            
                                                                                                                
FROM scratch                                                                                                    
COPY --from=builder /disk/* /disk/" > ./kubevirt-Dockerfile

docker build -f ./kubevirt-Dockerfile . -t $1