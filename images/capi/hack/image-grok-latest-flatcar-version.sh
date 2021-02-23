#!/bin/sh -ue

[[ -n ${DEBUG:-} ]] && set -o xtrace

channel="$1"

curl -L -s \
     "https://kinvolk.io/flatcar-container-linux/releases-json/releases-$channel.json" \
    | jq -r 'to_entries[] | "\(.key)"' \
    | grep -v "current" \
    | sort --version-sort \
    | tail -n1
