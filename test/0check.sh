#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

for file in "$DIR"/*.pl
do
    name=$(basename -s .pl $file)
    if ! [[ -f "$DIR/tmp/$name/output/0.COMPLETED" ]]; then
        echo "FAILED $file";
    fi
done

