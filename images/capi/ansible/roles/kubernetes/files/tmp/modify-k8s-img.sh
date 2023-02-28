#!/bin/bash

if [ "$#" -eq 0 ];then
  echo "Usage: $0 <name of tar file>"
else
  FILE=$1
  DIR="/tmp/${FILE%%.*}"
  mkdir -p ${DIR}
  tar xf /tmp/${FILE} -C ${DIR}
  sed -i "s/${FILE%%.*}\-amd64\:/${FILE%%.*}\:/" "${DIR}/manifest.json"
  sed -i "s/${FILE%%.*}\-amd64/${FILE%%.*}/" "${DIR}/repositories"
  tar cf "${DIR}.tar" -C ${DIR} .
  rm -rf ${DIR}
fi