#!/bin/sh

if [ "$#" -ne 2 ]; then
    echo "Error: Two arguments required"
    exit 1
fi

writefile="$1"
writestr="$2"

mkdir -p "$(dirname "$writefile")"

printf '%s\n' "$writestr" > "$writefile"
