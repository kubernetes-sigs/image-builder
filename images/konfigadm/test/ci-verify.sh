#!/bin/bash
set -e

[[ -e logs ]] && rm -rf logs
mkdir logs

image=$1
if [[ "$image" == "" ]]; then
  echo "Installing dependencies"
  make setup
  echo "Building new image"
  make ubuntu1804
  image=ubuntu1804.img
fi

echo "Testing image: $image"
konfigadm images build -vv --image $image --inline --capture-logs logs/  kubeadm.yml

# TODO: check kubeadm warnings etc..
cat logs/kubeadm.log | grep "Your Kubernetes control-plane has initialized successfully!"

image_count=$(cat logs/images-pre-init.txt | wc -l)

if [[ "$image_count" -lt 5 ]]; then
  echo "Kubernetes images not pre-pulled successfuly"
  exit 1
else
  echo "$image_count images pre-pulled successfully"
fi
