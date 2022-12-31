#!/bin/bash

/usr/bin/squeue -o "%.18i %9P %25j %.8u %.2t %.10M %.6D %15R %.6m" | /usr/bin/grep '\<efi\>' > /private_stores/gerlt/jobs/temp/efi.queue
#/usr/bin/squeue -o "%.18i %9P %25j %.8u %.2t %.10M %.6D %R" | /usr/bin/grep efi | /usr/bin/sed 's/\s\s*/ /g' | /usr/bin/sed 's/^\s*//' | /usr/bin/sort -t " " -k 3,3 | /usr/bin/awk '{printf("%18s %-9s %-25s %8s %2s %10s %6s %s\n",$1,$2,$3,$4,$5,$6,$7,$8)}' > /var/www/efi-web-dev/tmp/efi.queue

