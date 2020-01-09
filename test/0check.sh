#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

for file in "$DIR"/*.pl
do
    name=$(basename -s .pl $file)
    if ! [[ -f "$DIR/tmp/$name/output/1.out.completed" ]]; then
        ff="$DIR/tmp/$name/output"/eval-*
        echo "$ff"
        if ! [[ -f "$DIR/tmp/$name/output"/eval-*/COMPLETED ]]; then
            echo "FAILED $file";
        fi
    fi
done

