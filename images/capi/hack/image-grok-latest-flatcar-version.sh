#!/bin/bash -ue

[[ -n ${DEBUG:-} ]] && set -o xtrace

channel="$1"

curl -L -s \
     "https://$channel.release.flatcar-linux.net/amd64-usr/current/version.txt" \
    | grep '^FLATCAR_VERSION=' \
    | cut -d= -f2
