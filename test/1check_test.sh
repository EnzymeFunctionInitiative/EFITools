#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

for file in "$DIR"/*.pl
do
    name=$(basename $file .pl)
    if [[ -d "$DIR/tmp/$name/output" && ! -f "$DIR/tmp/$name/output/0.COMPLETED" ]]; then
        printf "\e[1;31mFAILED\e[0m  %-50s\n" $name;
    elif [[ "$name" == "cgfp_quantify" && -d "$DIR/tmp/cgfp_identify" ]]; then
        if [[ ! -f "$DIR/tmp/cgfp_identify/output/quantify-t_cgfp_qfy/0.COMPLETED" ]]; then
            printf "\e[1;31mFAILED\e[0m  %-50s\n" $name;
        else
            printf "\e[1;32mSUCCESS\e[0m %-50s ${dt:0:19}\n" $name
        fi
    elif [[ "$name" == "ssn_analyze_uniprot_full" && -d "$DIR/tmp/ssn_family_uniprot_full" ]]; then
        if [[ ! -f "$DIR/tmp/ssn_family_uniprot_full/output/eval-23-0-50000/0.COMPLETED" ]]; then
            printf "\e[1;31mFAILED\e[0m  %-50s\n" $name;
        else
            printf "\e[1;32mSUCCESS\e[0m %-50s ${dt:0:19}\n" $name
        fi
    elif [[ -d "$DIR/tmp/$name/output" && "$1" != "nodate" ]]; then
        dt=`stat -c "%y" "$DIR/tmp/$name/output/0.COMPLETED"`
        printf "\e[1;32mSUCCESS\e[0m %-50s ${dt:0:19}\n" $name
    fi
done

