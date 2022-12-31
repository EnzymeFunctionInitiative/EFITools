#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ "`ps -ef | grep $0 | grep -v grep | wc -l`" -gt 3 ]]; then echo "Already running; exiting (`ps -ef | grep $0 | grep -v grep`)"; exit; fi

source /etc/profile
module load Perl/5.28.1-IGB-gcc-8.2.0
source /home/groups/efi/apps/perl_env.sh

$DIR/job_manager.pl "$@"

