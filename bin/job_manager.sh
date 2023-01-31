#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Working in $DIR"
if [[ "`ps -ef | grep $0 | grep -v grep | wc -l`" -gt 3 ]]; then echo "Already running; exiting (`ps -ef | grep $0 | grep -v grep`)"; exit; fi
echo "Ok to proceed"

source /etc/profile
module load Perl/5.28.1-IGB-gcc-8.2.0
source /home/groups/efi/apps/perl_env.sh

lock_file="/tmp/job_manager.lock"

set +e

$DIR/job_manager.pl "$@" --lock-file $lock_file

rm -f $lock_file

