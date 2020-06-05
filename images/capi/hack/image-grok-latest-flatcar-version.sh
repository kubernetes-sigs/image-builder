#!/bin/sh -ue

channel="$1"

curl -s \
     "https://www.flatcar-linux.org/releases-json/releases-$channel.json" \
    | jq -r 'to_entries[] | "\(.key)"' \
    | grep -v "current" \
    | sort \
    | tail -n1
